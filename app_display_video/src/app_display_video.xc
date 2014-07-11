
#include <platform.h>

#include "lcd.h"
#include "sdram.h"
#include "display_controller.h"
#include "image_sensor.h"


// Port declaration
on tile[1] : image_sensor_ports imgports = { //circle slot
   XS1_PORT_1J, XS1_PORT_1K, XS1_PORT_1L, XS1_PORT_8C,
   {XS1_PORT_1H, XS1_PORT_1I, 1000}, XS1_CLKBLK_1
};

on tile[1] : img_snsr_slave_mode_ports imgports_slave = { // circle slot
  XS1_PORT_1E, XS1_PORT_1D, XS1_PORT_1P, XS1_PORT_1O
};

on tile[0] : lcd_ports lcdports = { //triangle slot
  XS1_PORT_1I, XS1_PORT_1L, XS1_PORT_16B, XS1_PORT_1J, XS1_PORT_1K, XS1_CLKBLK_1 };
on tile[0] : sdram_ports sdramports = { //star slot
  XS1_PORT_16A, XS1_PORT_1B, XS1_PORT_1G, XS1_PORT_1C, XS1_PORT_1F, XS1_CLKBLK_2 };

#define SENSOR_OPT_MODE  SLAVE_MODE  //MASTER_MODE - only two modes supported now

void app(streaming chanend c_img, chanend c_dc){

    unsigned frBuf[2], frBufIndex=0;

    // Create frame buffer
    frBuf[0] = display_controller_register_image(c_dc, LCD_ROW_WORDS, LCD_HEIGHT);
    frBuf[1] = display_controller_register_image(c_dc, LCD_ROW_WORDS, LCD_HEIGHT);
    display_controller_frame_buffer_init(c_dc, frBuf[0]);

    // Set capture window size
    image_sensor_set_capture_window(c_img, LCD_HEIGHT, LCD_WIDTH);


    // Get frames and display them
    while (1){

        frBufIndex = 1-frBufIndex;
        image_sensor_get_frame(c_img, c_dc, frBuf[frBufIndex], LCD_HEIGHT, LCD_WIDTH,SENSOR_OPT_MODE);

        display_controller_frame_buffer_commit(c_dc, frBuf[frBufIndex]);
        delay_milliseconds(10);   // To remove flicker

    }
}
int main(){
    chan c_dc, c_lcd, c_sdram;
    streaming chan c_img_sen;

    par{
        on tile[1]: image_sensor_server(imgports,imgports_slave,c_img_sen,SENSOR_OPT_MODE);

        on tile[0]: app(c_img_sen,c_dc);
        on tile[0]: display_controller(c_dc,c_lcd,c_sdram);
        on tile[0]: lcd_server(c_lcd,lcdports);
        on tile[0]: sdram_server(c_sdram,sdramports);
    }

    return 0;
}
