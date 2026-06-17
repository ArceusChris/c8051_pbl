#include <stdbool.h>
#include <stdint.h>
#include "board.h"

#define TIMER0_RELOAD (65536UL - (SYSCLK_HZ / 12UL / 1000UL))
#define MAX_LEVEL 32

typedef enum {
    GAME_IDLE,
    GAME_SHOW,
    GAME_INPUT,
    GAME_LEVEL_OK,
    GAME_FAIL
} game_state_t;

static volatile uint32_t g_ms;
static volatile uint8_t g_display_pos;
static volatile uint8_t g_display[4];
static volatile uint16_t g_beep_ms;
static volatile bool g_start_request;

static __xdata uint8_t sequence[MAX_LEVEL];
static uint8_t level;
static uint8_t input_pos;
static uint16_t score;
static uint16_t adc_value;
static uint16_t lfsr = 0xACE1u;
static uint32_t next_action_ms;
static uint32_t input_ready_ms;
static uint8_t playback_phase;
static bool input_wait_release;
static char g_key_raw;
static game_state_t state;

static const __code uint8_t seg_digits[10] = {
    0x3F, 0x06, 0x5B, 0x4F, 0x66,
    0x6D, 0x7D, 0x07, 0x7F, 0x6F
};

static uint32_t millis(void)
{
    uint32_t now;
    EA = 0;
    now = g_ms;
    EA = 1;
    return now;
}

static void led_write(uint8_t value)
{
    uint8_t mask;
#if LED_ACTIVE_LOW
    uint8_t shifted = (uint8_t)~value;
#else
    uint8_t shifted = value;
#endif

    for (mask = 0x80u; mask != 0u; mask >>= 1) {
        LED_SER_CLK = 0;
        LED_SER_DATA = (shifted & mask) ? 1 : 0;
        LED_SER_CLK = 1;
    }
    LED_SER_CLK = 0;
}

static void status_led_write(bool on)
{
#if STATUS_LED_ACTIVE_LOW
    STATUS_LED = on ? 0 : 1;
#else
    STATUS_LED = on ? 1 : 0;
#endif
}

static void buzzer_write(bool on)
{
#if BUZZER_ACTIVE_LOW
    BUZZER = on ? 0 : 1;
#else
    BUZZER = on ? 1 : 0;
#endif
}

static void beep(uint16_t duration_ms)
{
    g_beep_ms = duration_ms;
}

static uint8_t encode_char(char c)
{
    if (c >= '0' && c <= '9') {
        return seg_digits[(uint8_t)(c - '0')];
    }

    switch (c) {
    case 'A': return 0x77;
    case 'b': return 0x7C;
    case 'C': return 0x39;
    case 'd': return 0x5E;
    case 'E': return 0x79;
    case 'F': return 0x71;
    case 'G': return 0x3D;
    case 'H': return 0x76;
    case 'I': return 0x06;
    case 'L': return 0x38;
    case 'n': return 0x54;
    case 'O': return 0x3F;
    case 'o': return 0x5C;
    case 'P': return 0x73;
    case 'r': return 0x50;
    case 'U': return 0x3E;
    case '-': return 0x40;
    default: return 0x00;
    }
}

static void display_text(const char *text)
{
    uint8_t i;
    for (i = 0; i < 4; i++) {
        g_display[i] = encode_char(text[i]);
    }
}

static void display_number(uint16_t value)
{
    uint8_t i;
    bool nonzero = false;

    if (value > 9999u) {
        value = 9999u;
    }

    for (i = 0; i < 4; i++) {
        uint16_t div = (i == 0) ? 1000u : (i == 1) ? 100u : (i == 2) ? 10u : 1u;
        uint8_t digit = (uint8_t)(value / div);
        value %= div;
        if (digit || i == 3 || nonzero) {
            g_display[i] = seg_digits[digit];
            nonzero = true;
        } else {
            g_display[i] = 0;
        }
    }
}

static void display_scan_isr(void)
{
    uint8_t pattern = g_display[g_display_pos];
    uint8_t port_pattern =
        ((pattern & 0x01u) << 7) |
        ((pattern & 0x02u) << 5) |
        ((pattern & 0x04u) << 3) |
        ((pattern & 0x08u) << 1) |
        ((pattern & 0x10u) >> 1) |
        ((pattern & 0x20u) >> 3) |
        ((pattern & 0x40u) >> 5) |
        ((pattern & 0x80u) >> 7);

    SEG_PORT = 0x00;
    DIGIT_A = (g_display_pos & 0x01u) ? 1 : 0;
    DIGIT_B = (g_display_pos & 0x02u) ? 1 : 0;

#if SEG_ACTIVE_LOW
    SEG_PORT = (uint8_t)~port_pattern;
#else
    SEG_PORT = port_pattern;
#endif

    g_display_pos++;
    if (g_display_pos >= 4u) {
        g_display_pos = 0;
    }
}

static void timer0_isr(void) __interrupt(1)
{
    TH0 = (uint8_t)(TIMER0_RELOAD >> 8);
    TL0 = (uint8_t)TIMER0_RELOAD;
    g_ms++;
    display_scan_isr();

    if (g_beep_ms) {
        g_beep_ms--;
        buzzer_write(true);
    } else {
        buzzer_write(false);
    }
}

static void int0_isr(void) __interrupt(0)
{
    g_start_request = true;
}

static bool trigger_key_pressed(void)
{
    static bool last_raw = false;
    static bool last_sent = false;
    static uint32_t changed_ms;
    bool raw;
    uint32_t now = millis();

#if TRIGGER_KEY_ACTIVE_LOW
    raw = (TRIGGER_KEY == 0);
#else
    raw = (TRIGGER_KEY != 0);
#endif

    if (raw != last_raw) {
        last_raw = raw;
        changed_ms = now;
        return false;
    }

    if ((now - changed_ms) < 25u) {
        return false;
    }

    if (!raw) {
        last_sent = false;
        return false;
    }

    if (!last_sent) {
        last_sent = true;
        return true;
    }

    return false;
}

static void uart_putc(char c)
{
#if UART_ENABLE
    SBUF0 = c;
    while (!TI0) {
    }
    TI0 = 0;
#else
    (void)c;
#endif
}

static void uart_puts(const char *s)
{
    while (*s) {
        if (*s == '\n') {
            uart_putc('\r');
        }
        uart_putc(*s++);
    }
}

static void uart_put_uint(uint16_t value)
{
    char buf[6];
    int8_t i = 0;

    if (value == 0u) {
        uart_putc('0');
        return;
    }

    while (value && i < (int8_t)sizeof(buf)) {
        buf[i++] = (char)('0' + (value % 10u));
        value /= 10u;
    }
    while (i > 0) {
        uart_putc(buf[--i]);
    }
}

static void uart_log_level(const char *prefix)
{
    uart_puts(prefix);
    uart_puts(" level=");
    uart_put_uint(level);
    uart_puts(" score=");
    uart_put_uint(score);
    uart_puts(" adc=");
    uart_put_uint(adc_value);
    uart_puts("\n");
}

static void adc_init(void)
{
    REF0CN = 0x0E;
    AMX0N = 0x1F;
    AMX0P = ADC0_CHANNEL;
    ADC0CF = 0xF8;
    ADC0CN = 0x80;
}

static uint16_t adc_read(void)
{
    uint16_t value;
    AMX0P = ADC0_CHANNEL;
    ADC0CN &= (uint8_t)~0x20;
    ADC0CN |= 0x10;
    while (ADC0CN & 0x10) {
    }
    value = ((uint16_t)ADC0H << 8) | ADC0L;
    return value & 0x03FFu;
}

static uint16_t playback_interval_ms(void)
{
    uint16_t inverted = 1023u - (adc_value & 0x03FFu);
    return (uint16_t)(130u + (inverted / 4u));
}

static uint8_t random_led(void)
{
    uint16_t bit = (uint16_t)((lfsr ^ (lfsr >> 2) ^ (lfsr >> 3) ^ (lfsr >> 5)) & 1u);
    lfsr = (uint16_t)((lfsr >> 1) | (bit << 15));
    lfsr ^= (uint16_t)millis();
    lfsr ^= adc_value;
    return (uint8_t)(lfsr & 0x07u);
}

static void append_sequence_item(uint8_t index)
{
    if (index < MAX_LEVEL) {
        sequence[index] = random_led();
    }
}

static void game_reset(void)
{
    uint8_t i;
    level = 1;
    input_pos = 0;
    score = 0;
    playback_phase = 0;
    for (i = 0; i < MAX_LEVEL; i++) {
        append_sequence_item(i);
    }
    state = GAME_IDLE;
    led_write(0x00);
    status_led_write(false);
    display_text("PBL ");
}

static void game_start(void)
{
    level = 1;
    input_pos = 0;
    score = 0;
    append_sequence_item(0);
    playback_phase = 0;
    state = GAME_SHOW;
    next_action_ms = millis() + 500u;
    display_text("Go  ");
    status_led_write(true);
    beep(160);
    uart_log_level("start");
}

static char keypad_raw(void)
{
    static const __code char keymap[4][4] = {
        { '0', '4', '8', 'C' },
        { '1', '5', '9', 'D' },
        { '2', '6', 'A', 'E' },
        { '3', '7', 'B', 'F' }
    };
    uint8_t row;

    KEYPAD_PORT = KEYPAD_ROWS_MASK | KEYPAD_COLS_MASK;
    for (row = 0; row < 4u; row++) {
        uint8_t row_drive = (uint8_t)(KEYPAD_ROWS_MASK & (uint8_t)~(1u << row));
        uint8_t cols;
        uint8_t settle;

        KEYPAD_PORT = row_drive | KEYPAD_COLS_MASK;
        for (settle = 0; settle < 30u; settle++) {
            __asm nop __endasm;
        }
        cols = (uint8_t)((~KEYPAD_PORT & KEYPAD_COLS_MASK) >> 4);
        if (cols) {
            uint8_t col;
            for (col = 0; col < 4u; col++) {
                if (cols & (1u << col)) {
                    KEYPAD_PORT = KEYPAD_ROWS_MASK | KEYPAD_COLS_MASK;
                    return keymap[row][col];
                }
            }
        }
    }

    KEYPAD_PORT = KEYPAD_ROWS_MASK | KEYPAD_COLS_MASK;
    return 0;
}

static char keypad_get_key(void)
{
    static char last_raw;
    static char last_sent;
    static uint32_t changed_ms;
    char raw = keypad_raw();
    uint32_t now = millis();

    g_key_raw = raw;

    if (raw != last_raw) {
        last_raw = raw;
        changed_ms = now;
        return 0;
    }

    if ((now - changed_ms) < 25u) {
        return 0;
    }

    if (raw == 0) {
        last_sent = 0;
        return 0;
    }

    if (raw != last_sent) {
        last_sent = raw;
        return raw;
    }

    return 0;
}

static void handle_input_key(char key)
{
    uint8_t pressed;

    if (key < '1' || key > '8') {
        return;
    }

    pressed = (uint8_t)(key - '1');
    if (pressed == sequence[input_pos]) {
        led_write((uint8_t)(1u << pressed));
        beep(90);
        input_pos++;
        if (input_pos >= level) {
            score = (uint16_t)(score + level);
            if (level < MAX_LEVEL) {
                append_sequence_item(level);
                level++;
            }
            display_number(score);
            state = GAME_LEVEL_OK;
            next_action_ms = millis() + 700u;
            uart_log_level("ok");
        }
    } else {
        display_text("Err ");
        led_write(0xFF);
        status_led_write(false);
        beep(900);
        state = GAME_FAIL;
        next_action_ms = millis() + 1500u;
        uart_log_level("fail");
    }
}

static void game_update(char key)
{
    uint32_t now = millis();

    if (key == '#' || key == 'F') {
        game_reset();
        return;
    }

    if (g_start_request || key == '*' || key == 'C') {
        g_start_request = false;
        game_start();
        return;
    }

    switch (state) {
    case GAME_IDLE:
        if ((now / 150u) != ((now - 1u) / 150u)) {
            led_write((uint8_t)(1u << ((now / 150u) & 0x07u)));
        }
        break;

    case GAME_SHOW:
        if (now >= next_action_ms) {
            uint8_t step = (uint8_t)(playback_phase / 2u);
            if (step >= level) {
                playback_phase = 0;
                input_pos = 0;
                state = GAME_INPUT;
                input_wait_release = true;
                input_ready_ms = now + 250u;
                led_write(0x00);
                display_text("In  ");
                break;
            }
            if ((playback_phase & 1u) == 0u) {
                display_number((uint16_t)sequence[step] + 1u);
                led_write((uint8_t)(1u << sequence[step]));
                beep(120);
                next_action_ms = now + playback_interval_ms();
            } else {
                led_write(0x00);
                next_action_ms = now + 120u;
            }
            playback_phase++;
        }
        break;

    case GAME_INPUT:
        if (input_wait_release || now < input_ready_ms) {
            if (g_key_raw == 0 && now >= input_ready_ms) {
                input_wait_release = false;
            }
            break;
        }
        if (key != 0) {
            handle_input_key(key);
        }
        break;

    case GAME_LEVEL_OK:
        led_write(0xAA);
        status_led_write((now & 0x80u) != 0u);
        if (now >= next_action_ms) {
            playback_phase = 0;
            state = GAME_SHOW;
            display_number(level);
            next_action_ms = now + 400u;
        }
        break;

    case GAME_FAIL:
        if (now >= next_action_ms) {
            display_number(score);
            led_write(0x00);
            status_led_write(false);
            state = GAME_IDLE;
        }
        break;
    }
}

static void ports_init(void)
{
    P0SKIP = 0xCF;
    P1SKIP = 0xFF;
    P2SKIP = 0xFF;

    P0MDIN = 0xFF;
    P1MDIN = 0xFF;
    P2MDIN = 0xFF;
    P3MDIN = 0xFB;

    P0MDOUT = 0xD1;
    P1MDOUT = 0xFF;
    P2MDOUT = KEYPAD_ROWS_MASK;
    P3MDOUT = 0x1A;

    P0 = 0x3F;
    SEG_PORT = 0x00;
    P3 = 0xE5;
    KEYPAD_PORT = KEYPAD_ROWS_MASK | KEYPAD_COLS_MASK;
    led_write(0x00);
    status_led_write(false);
}

static void oscillator_init(void)
{
    OSCICN = 0x83;
}

static void uart_init(void)
{
#if UART_ENABLE
    SCON0 = 0x50;
    TMOD = (TMOD & 0x0Fu) | 0x20u;
    TH1 = (uint8_t)(256u - (SYSCLK_HZ / 12UL / 32UL / UART_BAUD));
    TL1 = TH1;
    TR1 = 1;
    TI0 = 1;
#endif
}

static void timer0_init(void)
{
    TMOD = (TMOD & 0xF0u) | 0x01u;
    TH0 = (uint8_t)(TIMER0_RELOAD >> 8);
    TL0 = (uint8_t)TIMER0_RELOAD;
    ET0 = 1;
    TR0 = 1;
}

static void interrupts_init(void)
{
    IT01CF = 0x01;
    IT0 = 1;
    EX0 = 1;
    EA = 1;
}

static void system_init(void)
{
    PCA0MD &= (uint8_t)~0x40;
    oscillator_init();
    ports_init();
    XBR0 = UART_ENABLE ? 0x01 : 0x00;
    XBR1 = 0x40;
    adc_init();
    uart_init();
    timer0_init();
    interrupts_init();
}

int main(void)
{
    uint32_t last_adc_ms = 0;

    system_init();
    game_reset();
    uart_puts("\nC8051F310 PBL memory challenge ready\n");
    uart_puts("Press C or INT0 to start, F to reset.\n");

    while (1) {
        char key = keypad_get_key();
        uint32_t now = millis();

        if ((now - last_adc_ms) >= 100u) {
            last_adc_ms = now;
            adc_value = adc_read();
        }

        if (trigger_key_pressed()) {
            g_start_request = true;
        }

        game_update(key);
    }
}
