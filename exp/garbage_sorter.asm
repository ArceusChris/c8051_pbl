	.module garbage_sorter

;===============================================================================
;  C8051F310 实验三：可回收垃圾分类回收系统（纯汇编）
;
;  硬件约定来自 C8051F310EVM 使用指南：
;    P1.7..P1.0  -> 四位数码管段控 a,b,c,d,e,f,g,dp，高电平点亮
;    P0.7/P0.6   -> 数码管位选 B/A，00/01/10/11 选择第 0/1/2/3 位
;    P2.0..P2.3  -> 矩阵键盘 KO.0..KO.3，行扫描输出
;    P2.4..P2.7  -> 矩阵键盘 KI.0..KI.3，列输入，上拉，按下读到低电平
;    P3.3/P3.4   -> 74HCT164 数据/时钟，控制 D1-D8 LED 阵列，低电平点亮
;    P3.1        -> 蜂鸣器，高电平有效
;    P0.1        -> KINT，外部中断 0，提前关盖
;
;  功能键：
;    K10/K11/K12/K13 -> F1/F2/F3/F4，选择 4 个垃圾桶
;    K14             -> F5，未输入数字时投 1 袋
;    K15             -> F6，四个桶容量全部置 9
;
;  内部约定：
;    keytmp = 'a'..'f' 表示 F1..F6。用小写是为了和数码管段码字符区分。
;===============================================================================

;------------------------------ SFR 地址定义 -----------------------------------
P0      = 0x80
SP      = 0x81
TMOD    = 0x89
TL0     = 0x8A
TH0     = 0x8C
P1      = 0x90
P2      = 0xA0
P0MDOUT = 0xA4
P1MDOUT = 0xA5
P2MDOUT = 0xA6
P3MDOUT = 0xA7
IE      = 0xA8
P3      = 0xB0
OSCICN  = 0xB2
P0SKIP  = 0xD4
P1SKIP  = 0xD5
P2SKIP  = 0xD6
PCA0MD  = 0xD9
XBR1    = 0xE2
IT01CF  = 0xE4
P0MDIN  = 0xF1
P1MDIN  = 0xF2
P2MDIN  = 0xF3
P3MDIN  = 0xF4

TR0     = 0x8C
IT0     = 0x88
EX0     = 0xA8
ET0     = 0xA9
EA      = 0xAF

BUZZER  = 0xB1
SERDAT  = 0xB3
SERCLK  = 0xB4

; Timer0 使用 SYSCLK/12。24.5MHz 下 1ms 重装约为 65536 - 2042 = F806h。
T0RH    = 0xF8
T0RL    = 0x06

;------------------------------ 内部 RAM 变量 ----------------------------------
	.area DSEG (DATA)
cap0:	.ds 4	; 四个垃圾桶剩余容量，范围 0..9
disp0:	.ds 4	; 四位数码管当前段码缓存，由定时中断轮流扫描
state:	.ds 1	; 0=无桶开盖，1=有桶开盖
active:	.ds 1	; 当前开盖桶编号，0..3
msflag:	.ds 1	; Timer0 每 1ms 置 1，主循环看到后处理软件计时
scanpos:.ds 1	; 当前扫描的数码管位，0..3
blink:	.ds 1	; 当前开盖桶数码管闪烁开关，0=灭，1=显示
seed:	.ds 1	; 伪随机种子，用 Timer0 低字节扰动
keytmp:	.ds 1	; 消抖后的键值
openlo:	.ds 1	; 开盖剩余时间低字节，单位 ms
openhi:	.ds 1	; 开盖剩余时间高字节，8000ms = 1F40h
beeplo:	.ds 1	; 蜂鸣剩余时间低字节，单位 ms
beephi:	.ds 1	; 蜂鸣剩余时间高字节，1000ms = 03E8h
blinkc:	.ds 1	; 100ms 闪烁分频计数
proglo:	.ds 1	; LED 进度条 1s 分频低字节
proghi:	.ds 1	; LED 进度条 1s 分频高字节
tempidx:.ds 1	; 临时提示显示在哪一位数码管
tempseg:.ds 1	; 临时提示段码，F=满，E=错误
templo:	.ds 1	; 临时提示剩余时间低字节
temphi:	.ds 1	; 临时提示剩余时间高字节
ledmask:.ds 1	; D1-D8 逻辑亮灭掩码，1=亮；输出到 74HCT164 前会取反
pending_amt:.ds 1 ; 数字键输入的本次投递袋数，0 表示未输入

;------------------------------ 中断向量 ---------------------------------------
	.area CODE (ABS)
	.org 0x0000
	ljmp start
	.org 0x0003
	ljmp int0_isr
	.org 0x000B
	ljmp timer0_isr

	.org 0x0100
start:
	; 上电入口：初始化硬件、生成四个容量、刷新显示。
	mov sp,#0x60
	lcall init_device
	lcall init_caps
	lcall update_display
	mov ledmask,#0x00
	lcall led_write

main:
	; 主循环尽量短：1ms 软计时、按键消抖、业务处理。
	; 数码管扫描放在 Timer0 ISR，避免主循环阻塞时显示熄灭。
	mov a,msflag
	jz no_tick
	mov msflag,#0
	lcall tick_1ms
no_tick:
	lcall debounce_key
	jz main
	mov keytmp,a
	lcall handle_key
	lcall wait_release
	sjmp main

;-------------------------------------------------------------------------------
; init_device
; 初始化 C8051F310 片上外设和 EVM 端口模式。
;-------------------------------------------------------------------------------
init_device:
	; 关闭看门狗。
	anl PCA0MD,#0xBF
	mov PCA0MD,#0x00
	; 内部 24.5MHz 振荡器。
	mov OSCICN,#0x83
	; 跳过非 UART/非外设引脚，打开 Crossbar。
	mov P0SKIP,#0xCF
	mov P1SKIP,#0xFF
	mov P2SKIP,#0xFF
	; P3.2 是 ADC 输入但本程序不用 ADC，仍保持数字输入安全。
	mov P0MDIN,#0xFF
	mov P1MDIN,#0xFF
	mov P2MDIN,#0xFF
	mov P3MDIN,#0xFF
	; P0.6/P0.7 位选输出，P0.0 D9 输出；P0.1 KINT 输入。
	mov P0MDOUT,#0xC1
	; P1 段码输出；P2 低四位键盘行输出，高四位列输入。
	mov P1MDOUT,#0xFF
	mov P2MDOUT,#0x0F
	; P3.1 蜂鸣器、P3.3/P3.4 74HCT164 输出。
	mov P3MDOUT,#0x1A
	mov P0,#0x3F
	mov P1,#0x00
	mov P2,#0xFF
	mov P3,#0xE5
	mov XBR1,#0x40
	; Timer0 16 位定时，1ms 中断。
	mov TMOD,#0x01
	mov TH0,#T0RH
	mov TL0,#T0RL
	; INT0 选择 P0.1，下降沿触发，用作 KINT 提前关盖。
	mov IT01CF,#0x01
	setb IT0
	setb EX0
	setb ET0
	setb EA
	setb TR0
	ret

;-------------------------------------------------------------------------------
; init_caps
; 生成四个 0..9 的初始容量。
;-------------------------------------------------------------------------------
init_caps:
	mov seed,#0x5A
	mov r0,#cap0
	mov r7,#4
cap_loop:
	lcall tiny_delay
	mov a,TL0
	xrl a,seed
	add a,#3
	mov seed,a
	anl a,#0x0F
	mov b,a
	clr c
	subb a,#10
	jnc cap_ge_10
	mov a,b
	sjmp cap_store
cap_ge_10:
	mov a,b
	clr c
	subb a,#6
cap_store:
	mov @r0,a
	inc r0
	djnz r7,cap_loop
	ret

tiny_delay:
	; 给 Timer0 低字节变化一点时间，用于初始化容量扰动。
	mov r6,#120
td1:	djnz r6,td1
	ret

;-------------------------------------------------------------------------------
; timer0_isr
; 1ms 周期中断：重装 Timer0、置 msflag、扫描一位数码管。
; 注意保存 R0：display_scan 使用 R0，主程序也用 R0 指向容量数组。
;-------------------------------------------------------------------------------
timer0_isr:
	push acc
	push psw
	push 0x00
	mov TH0,#T0RH
	mov TL0,#T0RL
	mov msflag,#1
	lcall display_scan
	pop 0x00
	pop psw
	pop acc
	reti

;-------------------------------------------------------------------------------
; int0_isr
; KINT 提前关盖：停止计时、清空待投数量、关闭 LED 进度条、恢复容量显示。
;-------------------------------------------------------------------------------
int0_isr:
	mov state,#0
	mov pending_amt,#0
	mov ledmask,#0
	lcall led_write
	lcall update_display
	reti

;-------------------------------------------------------------------------------
; tick_1ms
; 主循环中的 1ms 软任务：
;   1. 蜂鸣器倒计时
;   2. F/E 临时提示倒计时
;   3. 开盖 8s 倒计时
;   4. 当前桶数码管 5Hz 闪烁
;   5. D1-D8 每秒减少一格，作为剩余时间进度条
;-------------------------------------------------------------------------------
tick_1ms:
	mov a,beeplo
	orl a,beephi
	jz beep_off
	setb BUZZER
	lcall dec_beep
	sjmp tick_open
beep_off:
	clr BUZZER

tick_open:
	mov a,templo
	orl a,temphi
	jz no_temp
	lcall dec_temp
	mov a,templo
	orl a,temphi
	jnz no_temp
	lcall update_display
no_temp:
	mov a,state
	jz tick_done
	lcall dec_open
	mov a,openlo
	orl a,openhi
	jnz still_open
	mov state,#0
	mov pending_amt,#0
	mov ledmask,#0
	lcall led_write
	lcall update_display
	ret
still_open:
	djnz blinkc,no_blink
	mov blinkc,#100
	mov a,blink
	xrl a,#1
	mov blink,a
	lcall update_display
no_blink:
	lcall dec_prog
	mov a,proglo
	orl a,proghi
	jnz tick_done
	mov proglo,#0xE8
	mov proghi,#0x03
	mov a,ledmask
	clr c
	rrc a
	mov ledmask,a
	lcall led_write
tick_done:
	ret

dec_beep:
	; 蜂鸣器 16 位倒计时，beephi:beeplo 每 1ms 减 1。
	mov a,beeplo
	jnz db_lo
	mov a,beephi
	jz db_ret
	dec beephi
	mov beeplo,#255
	ret
db_lo:	dec beeplo
db_ret:	ret

dec_temp:
	; 临时提示 16 位倒计时，结束后 update_display 恢复容量显示。
	mov a,templo
	jnz dt_lo
	mov a,temphi
	jz dt_ret
	dec temphi
	mov templo,#255
	ret
dt_lo:	dec templo
dt_ret:	ret

dec_open:
	; 开盖 16 位倒计时，8000ms 从 1F40h 开始减。
	mov a,openlo
	jnz do_lo
	mov a,openhi
	jz do_ret
	dec openhi
	mov openlo,#255
	ret
do_lo:	dec openlo
do_ret:	ret

dec_prog:
	; LED 进度条分频，1000ms 到 0 后熄灭一格。
	mov a,proglo
	jnz dp_lo
	mov a,proghi
	jz dp_ret
	dec proghi
	mov proglo,#255
	ret
dp_lo:	dec proglo
dp_ret:	ret

;-------------------------------------------------------------------------------
; handle_key
; 按键业务分发：
;   'a'..'d' = F1..F4：无开盖则开对应桶；已开同一桶则投 1 袋。
;   'e'      = F5：投 1 袋。
;   'f'      = F6：四个桶容量全部置 9。
;   '1'..'9' = 开盖后直接投入对应袋数。
;-------------------------------------------------------------------------------
handle_key:
	mov a,keytmp
	cjne a,#'a',hk_b
	mov r7,#0
	sjmp hk_bin
hk_b:	cjne a,#'b',hk_c
	mov r7,#1
	sjmp hk_bin
hk_c:	cjne a,#'c',hk_d
	mov r7,#2
	sjmp hk_bin
hk_d:	cjne a,#'d',hk_e
	mov r7,#3
hk_bin:
	; 未开盖：打开对应桶；已开盖：只有同一个桶键才继续投 1 袋。
	mov a,state
	jz open_bin
	mov a,active
	mov b,r7
	cjne a,b,hk_ret
	sjmp deliver_one
hk_ret:	ret

hk_e:	cjne a,#'e',hk_f
	; F5：不输入数字时投 1 袋。batch_deliver 中把 0 当作 1。
	lcall batch_deliver
	ret

hk_f:	cjne a,#'f',hk_num
	; F6：演示/调试用，四个桶全部补满。
	lcall fill_caps
	ret

hk_num:
	; 数字 1..9 只在开盖状态有效，按下后立即尝试批量投递。
	mov a,state
	jz hk_ret
	mov a,keytmp
	clr c
	subb a,#'1'
	jc hk_ret
	cjne a,#9,hk_num_range
hk_num_range:
	jnc hk_ret
	inc a
	mov pending_amt,a
	lcall batch_deliver
	ret

fill_caps:
	; F6：四个容量全置 9，同时关闭当前开盖状态和 LED 进度条。
	mov cap0,#9
	mov cap0+1,#9
	mov cap0+2,#9
	mov cap0+3,#9
	mov state,#0
	mov pending_amt,#0
	mov ledmask,#0
	lcall led_write
	lcall update_display
	ret

open_bin:
	; F1-F4 第一次按下：如果桶非满，则开盖 8s。
	mov a,r7
	add a,#cap0
	mov r0,a
	mov a,@r0
	jz reject
	; 第一次开盖也算投递 1 袋，所以这里立即减容量。
	dec @r0
	mov active,r7
	mov state,#1
	mov pending_amt,#0
	mov openlo,#0x40
	mov openhi,#0x1F
	mov blink,#1
	mov blinkc,#100
	mov proglo,#0xE8
	mov proghi,#0x03
	mov ledmask,#0xFF
	lcall led_write
	lcall update_display
	ret

deliver_one:
	; 开盖期间再次按同一 F1-F4：投递 1 袋。
	mov a,r7
	add a,#cap0
	mov r0,a
	mov a,@r0
	jz reject
	dec @r0
	mov pending_amt,#0
	lcall update_display
	ret

reject:
	; 桶容量为 0：蜂鸣 1s，并在对应数码管显示 F。
	mov beeplo,#0xE8
	mov beephi,#0x03
	mov tempidx,r7
	mov tempseg,#0x8E
	mov templo,#0xE8
	mov temphi,#0x03
	lcall update_display
	ret

batch_deliver:
	; 多袋投递：pending_amt=0 表示 F5 投 1 袋；否则投 pending_amt 袋。
	mov a,state
	jz bd_ret
	mov a,pending_amt
	jnz bd_have_amount
	mov pending_amt,#1
bd_have_amount:
	mov a,active
	add a,#cap0
	mov r0,a
	mov a,@r0
	clr c
	subb a,pending_amt
	; 超过剩余容量时 CY=1，跳到错误处理，容量不变。
	jc batch_error
	mov @r0,a
	mov pending_amt,#0
	lcall update_display
bd_ret:	ret

batch_error:
	; 批量投递超量：蜂鸣 1s，并在当前桶显示 E。
	mov beeplo,#0xE8
	mov beephi,#0x03
	mov a,active
	mov tempidx,a
	mov tempseg,#0x9E
	mov templo,#0xE8
	mov temphi,#0x03
	mov pending_amt,#0
	lcall update_display
	ret

;-------------------------------------------------------------------------------
; update_display
; 把 cap0..cap3 转换成 disp0..disp3 段码缓存。
; 开盖桶按 blink 闪烁；临时 F/E 提示优先覆盖对应位。
;-------------------------------------------------------------------------------
update_display:
	mov r0,#cap0
	mov r1,#disp0
	mov r7,#4
ud_loop:
	mov a,@r0
	mov dptr,#seg_table
	movc a,@a+dptr
	mov @r1,a
	inc r0
	inc r1
	djnz r7,ud_loop

	; blink=0 时把当前开盖桶对应的显示位清空。
	mov a,state
	jz ud_temp
	mov a,blink
	jnz ud_temp
	mov a,active
	add a,#disp0
	mov r0,a
	mov @r0,#0x00

ud_temp:
	; 如果临时提示倒计时未结束，则显示 tempseg。
	mov a,templo
	orl a,temphi
	jz ud_ret
	mov a,tempidx
	add a,#disp0
	mov r0,a
	mov @r0,tempseg
ud_ret:	ret

;-------------------------------------------------------------------------------
; display_scan
; 动态扫描 4 位数码管。Timer0 ISR 每 1ms 调用一次，只刷新一位。
;-------------------------------------------------------------------------------
display_scan:
	mov a,scanpos
	anl a,#0x03
	mov scanpos,a
	add a,#disp0
	mov r0,a
	mov P1,#0x00
	mov a,scanpos
	anl a,#0x01
	jz ds_a0
	orl P0,#0x40
	sjmp ds_b
ds_a0:	anl P0,#0xBF
ds_b:	mov a,scanpos
	anl a,#0x02
	jz ds_b0
	orl P0,#0x80
	sjmp ds_seg
ds_b0:	anl P0,#0x7F
ds_seg:
	mov a,@r0
	mov P1,a
	inc scanpos
	ret

;-------------------------------------------------------------------------------
; led_write
; 将 ledmask 移入 74HCT164。
; ledmask bit=1 表示逻辑点亮；EVM 上 Q=0 亮，所以输出前 CPL。
;-------------------------------------------------------------------------------
led_write:
	mov a,ledmask
	cpl a
	mov r5,a
	mov r6,#8
lw_loop:
	clr SERCLK
	mov a,r5
	rlc a
	mov r5,a
	mov SERDAT,c
	setb SERCLK
	djnz r6,lw_loop
	clr SERCLK
	ret

;-------------------------------------------------------------------------------
; scan_key
; 矩阵键盘裸扫描，不带消抖。
; 返回 A=0 表示无键；数字键为 '0'..'9'；F1..F6 为 'a'..'f'。
;-------------------------------------------------------------------------------
scan_key:
	mov P2,#0xFE
	lcall settle
	mov a,P2
	cpl a
	anl a,#0xF0
	jnz row0
	mov P2,#0xFD
	lcall settle
	mov a,P2
	cpl a
	anl a,#0xF0
	jnz row1
	mov P2,#0xFB
	lcall settle
	mov a,P2
	cpl a
	anl a,#0xF0
	jnz row2
	mov P2,#0xF7
	lcall settle
	mov a,P2
	cpl a
	anl a,#0xF0
	jnz row3
	clr a
	ret

row0:	jb 0xE4,ret_0
	jb 0xE5,ret_4
	jb 0xE6,ret_8
	; P2.0 + P2.7 -> K12 -> F3
	mov a,#'c'
	ret
row1:	jb 0xE4,ret_1
	jb 0xE5,ret_5
	jb 0xE6,ret_9
	; P2.1 + P2.7 -> K13 -> F4
	mov a,#'d'
	ret
row2:	jb 0xE4,ret_2
	jb 0xE5,ret_6
	; P2.2 + P2.6 -> K10 -> F1
	jb 0xE6,ret_f1
	; P2.2 + P2.7 -> K14 -> F5
	mov a,#'e'
	ret
row3:	jb 0xE4,ret_3
	jb 0xE5,ret_7
	; P2.3 + P2.6 -> K11 -> F2
	jb 0xE6,ret_f2
	; P2.3 + P2.7 -> K15 -> F6
	mov a,#'f'
	ret
ret_0:	mov a,#'0'
	ret
ret_1:	mov a,#'1'
	ret
ret_2:	mov a,#'2'
	ret
ret_3:	mov a,#'3'
	ret
ret_4:	mov a,#'4'
	ret
ret_5:	mov a,#'5'
	ret
ret_6:	mov a,#'6'
	ret
ret_7:	mov a,#'7'
	ret
ret_8:	mov a,#'8'
	ret
ret_9:	mov a,#'9'
	ret
ret_f1:	mov a,#'a'
	ret
ret_f2:	mov a,#'b'
	ret

settle:
	; 行线切换后的短稳定延时。
	mov r4,#20
st1:	djnz r4,st1
	ret

wait_release:
	; 松手确认：先等 scan_key 读到无键，再延时复查一次。
	lcall scan_key
	jnz wait_release
	lcall debounce_delay
	lcall scan_key
	jnz wait_release
	ret

debounce_key:
	; 按下确认：两次扫描结果一致才返回键值，否则返回 0。
	lcall scan_key
	jz dbk_ret
	mov keytmp,a
	lcall debounce_delay
	lcall scan_key
	cjne a,keytmp,dbk_none
	ret
dbk_none:
	clr a
dbk_ret:
	ret

debounce_delay:
	; 软件消抖延时。Timer0 中断仍会继续扫描数码管。
	mov r5,#40
dbd1:	mov r6,#250
dbd2:	djnz r6,dbd2
	djnz r5,dbd1
	ret

seg_table:
	; 数码管段码 0..9，P1.7..P1.0 = a,b,c,d,e,f,g,dp。
	.db 0xFC,0x60,0xDA,0xF2,0x66,0xB6,0xBE,0xE0,0xFE,0xE6
