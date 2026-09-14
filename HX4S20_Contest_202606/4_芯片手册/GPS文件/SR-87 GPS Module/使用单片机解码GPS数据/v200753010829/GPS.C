
/*************************************
	GPS解码1602显示程序
	作者：BG4UVR
最后更新：
2007.01.27
	1.2版，改时间由RMC语句解码，取消日期显示
2007.01.25
	1.1版，修正定位后页面不能转换的BUG。
	1.0版，基本功能。
***************************************/

#include <reg2051.h>
#include "1602.h"

sbit GPS_SPD=P1^1;
sbit SPD_TYPE=P1^0;
sbit KEY1=P3^7;

/*
sbit GPS_SPD=P1^4;
sbit KEY1=P1^6;
sbit SPD_TYPE=P1^5;
*/

//各位见笑了，加密存储开机版权信息。免得被人改目标代码 :D
unsigned char code info[]={	'D'^0xab,'e'^0xab,'s'^0xab,'i'^0xab,'g'^0xab,'n'^0xab,' '^0xab,'b'^0xab,
							'y'^0xab,' '^0xab,'B'^0xab,'G'^0xab,'4'^0xab,'U'^0xab,'V'^0xab,'R'^0xab,};

char code TIME_AREA= 8;			//时区

//GPS数据存储数组
unsigned char JD[10];			//经度
unsigned char JD_a;			//经度方向
unsigned char WD[9];			//纬度
unsigned char WD_a;			//纬度方向
unsigned char time[6];		//时间
unsigned char speed[5];		//速度
unsigned char high[6];		//高度
unsigned char angle[5];		//方位角
unsigned char use_sat[2];		//使用的卫星数
unsigned char total_sat[2];	//天空中总卫星数
unsigned char lock;			//定位状态

//串口中断需要的变量
unsigned char seg_count;		//逗号计数器
unsigned char dot_count;		//小数点计数器
unsigned char byte_count;		//位数计数器
unsigned char cmd_number;		//命令类型
unsigned char mode;				//0：结束模式，1：命令模式，2：数据模式
unsigned char buf_full;			//1：整句接收完成，相应数据有效。0：缓存数据无效。
unsigned char cmd[5];			//命令类型存储数组

//显示需要的变量
unsigned int dsp_count;		//刷新次数计数器
unsigned char time_count;
bit page;
bit spd_type;

void sys_init(void);
bit chk_key(void);

main()
{
	unsigned char i;
	char Bhour;
	unsigned int Knots;
	sys_init();

	while(1){
		if(buf_full==0)				//无GPS信号时
		{
			dsp_count++;
			if(dsp_count>=65000){
				LCD_cls();			//清屏
				LCD_write_string(0,0,"No GPS connect..");
				while(buf_full==0);
				LCD_cls();	
				dsp_count=0;
			}
		}
		else{						//有GPS信号时
			if(chk_key()){				//检测到按键切换显示
				page=!page;
				LCD_cls();
			}

			if(!page){						//页面1
				if(buf_full|0x01){				//GGA语句
					if(lock=='0'){					//如果未定位
						LCD_write_string(0,0,"*---.--.----  ");
						LCD_write_string(0,1,"* --.--.----  ");					
					}else{							//如果已定位
						LCD_write_char(0,0,JD_a);			//显示经度
						for(i=0;i<3;i++){
							LCD_write_char(i+1,0,JD[i]);
						}
						LCD_write_char(4,0,'.');
						for(i=3;i<10;i++){
							LCD_write_char(i+2,0,JD[i]);
						}

						LCD_write_char(0,1,WD_a);			//显示纬度
						LCD_write_char(1,1,' ');
						for(i=0;i<2;i++){
							LCD_write_char(i+2,1,WD[i]);
						}			
						LCD_write_char(4,1,'.');
						for(i=2;i<9;i++){
							LCD_write_char(i+3,1,WD[i]);
						}							}
					LCD_write_char(14,0,use_sat[0]);		//显示接收卫星数
					LCD_write_char(15,0,use_sat[1]);
					buf_full&=~0x01;
					dsp_count=0;
				}
				if(buf_full|0x02){				//GSV语句
					LCD_write_char(14,1,total_sat[0]);
					LCD_write_char(15,1,total_sat[1]);
					buf_full&=~0x02;
					dsp_count=0;
				}
				if(buf_full|0x04){
					buf_full&=~0x04;
					dsp_count=0;
				}
			}
			else{							//页面2
				if(buf_full|0x01){				//GGA语句
					buf_full&=~0x01;
					dsp_count=0;
				}
				if(buf_full|0x02){
					buf_full&=~0x02;
					dsp_count=0;
				}
				if(buf_full|0x04){				//RMC语句
					Bhour=((time[0]-0x30)*10+time[1]-0x30)+TIME_AREA;
					if(Bhour>=24){
						Bhour-=24;
					}else if(Bhour<0){
						Bhour+=24;
					}
					LCD_write_string(2,1,"BJT ");
					LCD_write_char(6,1,Bhour/10+0x30);
					LCD_write_char(7,1,Bhour%10+0x30);
					LCD_write_char(8,1,':');
					LCD_write_char(9,1,time[2]);
					LCD_write_char(10,1,time[3]);
					LCD_write_char(11,1,':');
					LCD_write_char(12,1,time[4]);
					LCD_write_char(13,1,time[5]);
					if(spd_type){
						LCD_write_string(5,0,"km/h A");
					}else{
						LCD_write_string(5,0,"knot A");
					}
					if(lock=='0'){					//如果未定位
						LCD_write_string(0,0,"---.-");
						LCD_write_string(11,0,"---.-");
					}else{							//已经定位
						if(spd_type){					//km/h显示
							for(i=0;i<5;i++){
								LCD_write_char(i,0,speed[i]);
							}
						}else{							//knot显示
							Knots=	(((speed[0]-0x30)*1000
									+(speed[1]-0x30)*100
									+(speed[2]-0x30)*10
									+(speed[4]-0x30))*1000)/1852;
							LCD_write_char(0,0,Knots/1000+0x30);
							LCD_write_char(1,0,(Knots%1000)/100+0x30);
							LCD_write_char(2,0,(Knots%100)/10+0x30);
							LCD_write_char(3,0,'.');
							LCD_write_char(4,0,Knots%10+0x30);
						}
						for(i=0;i<5;i++){
							LCD_write_char(11+i,0,angle[i]);
						}
					}
					buf_full&=~0x04;
					dsp_count=0;
				}
			}
		}
	}
}

bit chk_key(void)
{
	if(!KEY1){
		delayms(10);
		if(!KEY1){
			while(!KEY1);
			delayms(10);
			return(1);
		}
	}
	return(0);
}

//系统初始化
void sys_init() {
	unsigned char i;
	SCON = 0x50; 	/* SCON: mode 1, 8-bit UART, enable rcvr */
	TMOD = 0x21; 	/* TMOD: timer 1, mode 2, 8-bit reload */
	if(GPS_SPD){
		TH1 = 0xfd; 		/* TH1: reload value for 9600 baud @ 11.059MHz */
	}else{
		TH1 = 0xfa;			/* TH1: reload value for 4800 baud @ 11.059MHz */
	}
	if(SPD_TYPE){
		spd_type=1;			//速度单位km/h
	}else{
		spd_type=0;			//速度单位knot
	}
	TR1 = 1; 		/* TR1: timer 1 run */
	LCD_init();		//初始化LCD
	LCD_write_string(0,0,"GPS Monitor V1.2");
	for(i=0;i<16;i++){								//显示版权信息
		LCD_write_char(i,1,info[i]^0xab);
	}
	for(i=1;i<4;i++){
		delayms(250);
	}
	LCD_cls();
	IE=0x90;			//开总中断、串口中断
}

//串口接收中断
void uart(void) interrupt 4
{
	unsigned char tmp;
	if(RI){
		tmp=SBUF;
		switch(tmp){
			case '$':
				cmd_number=0;		//命令类型清空
				mode=1;				//接收命令模式
				byte_count=0;		//接收位数清空
				break;
			case ',':
				seg_count++;		//逗号计数加1
				byte_count=0;
				break;
			case '*':
				switch(cmd_number){
					case 1:
						buf_full|=0x01;
						break;
					case 2:
						buf_full|=0x02;
						break;
					case 3:
						buf_full|=0x04;
						break;
				}
				mode=0;
				break;
			default:
				if(mode==1){
					//命令种类判断
					cmd[byte_count]=tmp;			//接收字符放入类型缓存
					if(byte_count>=4){				//如果类型数据接收完毕，判断类型
						if(cmd[0]=='G'){
							if(cmd[1]=='P'){
								if(cmd[2]=='G'){
									if(cmd[3]=='G'){
										if(cmd[4]=='A'){
											cmd_number=1;
											mode=2;
											seg_count=0;
											byte_count=0;
										}
									}
									else if(cmd[3]=='S'){
										if(cmd[4]=='V'){
											cmd_number=2;
											mode=2;
											seg_count=0;
											byte_count=0;
										}
									}
								}
								else if(cmd[2]=='R'){
									if(cmd[3]=='M'){
										if(cmd[4]=='C'){
											cmd_number=3;
											mode=2;
											seg_count=0;
											byte_count=0;
										}
									}
								}
							}
						}
					}
				}
				else if(mode==2){
					//接收数据处理
					switch (cmd_number){
						case 1:				//类型1数据接收。GPGGA
							switch(seg_count){
								case 2:								//纬度处理
									if(byte_count<9){
										WD[byte_count]=tmp;
									}
									break;
								case 3:								//纬度方向处理
									if(byte_count<1){
										WD_a=tmp;
									}
									break;
								case 4:								//经度处理
									if(byte_count<10){
										JD[byte_count]=tmp;
									}
									break;
								case 5:								//经度方向处理
									if(byte_count<1){
										JD_a=tmp;
									}
									break;
								case 6:								//定位判断
									if(byte_count<1){
										lock=tmp;
									}
									break;
								case 7:								//定位使用的卫星数
									if(byte_count<2){
										use_sat[byte_count]=tmp;
									}
									break;
								case 9:								//高度处理
									if(byte_count<6){
										high[byte_count]=tmp;
									}
									break;
							}
							break;
						case 2:				//类型2数据接收。GPGSV
							switch(seg_count){
								case 3:								//天空中的卫星总数
									if(byte_count<2){
										total_sat[byte_count]=tmp;
									}
									break;
							}
							break;
						case 3:				//类型3数据接收。GPRMC
							switch(seg_count){
								case 1:
									if(byte_count<6){				//时间处理
										time[byte_count]=tmp;	
									}
									break;
								case 7:								//速度处理
									if(byte_count<5){
										speed[byte_count]=tmp;
									}
									break;
								case 8:								//方位角处理
									if(byte_count<5){
										angle[byte_count]=tmp;
									}
									break;
							}
							break;
					}
				}
				byte_count++;		//接收数位加1
				break;
		}
	}
	RI=0;
}

/*
$GPGGA,024518.00,3153.7225,N,12111.9951,E,1,04,1.48,-00009,M,007,M,,*4C
$GPGLL,3153.7225,N,12111.9951,E,024518.00,A,A*63
$GPVTG,000.0,T,004.7,M,000.0,N,000.0,K,A*20
$GPGSA,A,2,04,08,17,20,,,,,,,,,1.48,1.48,0.03*08
$GPGSV,2,1,08,04,15,231,38,08,29,218,42,11,49,043,,19,09,082,*76
$GPGSV,2,2,08,27,14,198,29,28,71,316,,17,32,300,36,20,45,124,43*70
$GPRMC,024518.00,A,3153.7225,N,12111.9951,E,000.0,000.0,280107,04.7,W,A*12
$GPZDA,024519.45,28,01,2007,,*62

$GPGGA,024519.00,3153.7225,N,12111.9951,E,1,04,1.48,-00009,M,007,M,,*4D
$GPGLL,3153.7225,N,12111.9951,E,024519.00,A,A*62
$GPVTG,000.0,T,004.7,M,000.0,N,000.0,K,A*20
$GPGSA,A,2,04,08,17,20,,,,,,,,,1.48,1.48,0.03*08
$GPGSV,2,1,08,04,15,231,38,08,29,218,42,11,49,043,,19,09,082,*76
$GPGSV,2,2,08,27,14,198,29,28,71,316,,17,32,300,36,20,45,124,43*70
$GPRMC,024519.00,A,3153.7225,N,12111.9951,E,000.0,000.0,280107,04.7,W,A*13
$GPZDA,024520.49,28,01,2007,,*64

$GPGGA,024520.00,3153.7225,N,12111.9951,E,1,04,1.48,-00009,M,007,M,,*47
$GPGLL,3153.7225,N,12111.9951,E,024520.00,A,A*68
$GPVTG,000.0,T,004.7,M,000.0,N,000.0,K,A*20
$GPGSA,A,2,04,08,17,20,,,,,,,,,1.48,1.48,0.03*08
$GPGSV,2,1,08,04,15,231,38,08,29,218,42,11,49,043,,19,09,082,*76
$GPGSV,2,2,08,27,14,198,,28,71,316,,17,32,300,36,20,45,124,43*7B
$GPRMC,024520.00,A,3153.7225,N,12111.9951,E,000.0,000.0,280107,04.7,W,A*19
$GPZDA,024521.45,28,01,2007,,*69
*/