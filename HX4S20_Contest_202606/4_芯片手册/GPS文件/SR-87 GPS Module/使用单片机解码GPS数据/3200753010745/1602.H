
/*
sbit LCD_DB4= P0^4;
sbit LCD_DB5= P0^5;
sbit LCD_DB6= P0^6;
sbit LCD_DB7= P0^7;
sbit LCD1602_RS=P2^0;   
sbit LCD1602_RW=P2^1;//实际上没有读LCM,RW脚可以直接接地   
sbit LCD1602_EN=P2^2; 
*/


sbit LCD_DB4= P1^4;
sbit LCD_DB5= P1^5;
sbit LCD_DB6= P1^6;
sbit LCD_DB7= P1^7;
sbit LCD1602_RS=P1^3;   
//sbit LCD1602_RW=0;//实际上没有读LCM,RW脚可以直接接地   
sbit LCD1602_EN=P1^2; 


void LCD_write_char( unsigned x,unsigned char y,unsigned char dat);	//在指定位置显示字符
void LCD_write_string(unsigned char X,unsigned char Y,unsigned char *s);//在指定位置显示字符串
void LCD_cls(void);//清屏
void LCD_en_command(unsigned char command);
void LCD_en_dat(unsigned char temp);
void LCD_set_xy( unsigned char x, unsigned char y );
void LCD_init(void);
void SET_LCD(unsigned char IO_temp);
void delayms(unsigned char ms);
void lcddelay(void);

unsigned char LCDIO; 

void LCD_cls(void)
{
	LCD_en_command(0x01);	
    delayms(2);
}

void LCD_en_command(unsigned char command)
{
	LCD1602_RS=0;   
//	LCD1602_RW=0;
	LCD1602_EN=0;
	LCDIO=(command & 0xf0);
	SET_LCD(LCDIO);
	LCD1602_EN=1;
	lcddelay();
	LCD1602_EN=0;
	LCDIO=(command & 0x0f)<<4;
	SET_LCD(LCDIO);
	LCD1602_EN=1;
	lcddelay();
	LCD1602_EN=0;
}

void SET_LCD(unsigned char IO_temp)
{   
	LCD_DB7=IO_temp&0x80;
	LCD_DB6=IO_temp&0x40;
	LCD_DB5=IO_temp&0x20;
	LCD_DB4=IO_temp&0x10;
}

void LCD_en_dat(unsigned char dat)
{
	LCD1602_RS=1;
//	LCD1602_RW=0;
	LCD1602_EN=0;
	LCDIO=(dat & 0xf0);
	SET_LCD(LCDIO);
	LCD1602_EN=1;
	lcddelay();
	LCD1602_EN=0;
	LCDIO=(dat & 0x0f)<<4;
	SET_LCD(LCDIO);
	LCD1602_EN=1;
	lcddelay();
	LCD1602_EN=0;
}

void LCD_set_xy( unsigned char x, unsigned char y )
{
	unsigned char address;
	if (y ==0) 
		address = 0x80 + x;
	else 
		address = 0xC0 + x;
		LCD_en_command(address); 
}

void LCD_write_char( unsigned x,unsigned char y,unsigned char dat)
{
	LCD_set_xy( x, y ); 
	LCD_en_dat(dat);
}

void LCD_write_string(unsigned char X,unsigned char Y,unsigned char *s)
{
    LCD_set_xy( X, Y );    //set address 
    while (*s)       // write character
    {
		LCDIO=*s;
		SET_LCD(LCDIO);
		LCD_en_dat(*s);   
		s ++;
    }
}

void LCD_init(void)
{
	LCD_en_command(0x33);
	delayms(20);
	LCD_en_command(0x32);
	delayms(20);
	LCD_en_command(0x08);
	delayms(5);
	LCD_en_command(0x01);
	delayms(5);
	LCD_en_command(0x06);
	delayms(5);
	LCD_en_command(0x0c);
	delayms(5);
}

void delayms(unsigned char ms)	
{
	unsigned char i;
	while(ms--)
	{
		for(i = 0; i < 115; i++);
	}
}

void lcddelay(void)	
{
	unsigned char i;
	for(i = 0; i < 2; i++);
}
