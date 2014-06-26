
#include <platform.h>

#include "lcd.h"
#include "sdram.h"
#include "display_controller.h"
#include "image_sensor.h"


// Port declaration
on tile[1] : image_sensor_ports imgports = { //circle slot
   XS1_PORT_1J, XS1_PORT_1K, XS1_PORT_1L, XS1_PORT_16B,
   {XS1_PORT_1H, XS1_PORT_1I, 1000}, XS1_CLKBLK_1
};

on tile[1] : img_snsr_slave_mode_ports imgports_slave = { // circle slot
  XS1_PORT_1E, XS1_PORT_1D, XS1_PORT_1P, XS1_PORT_1O
};

on tile[0] : lcd_ports lcdports = { //triangle slot
  XS1_PORT_1I, XS1_PORT_1L, XS1_PORT_16B, XS1_PORT_1J, XS1_PORT_1K, XS1_CLKBLK_1 };
on tile[0] : sdram_ports sdramports = { //star slot
  XS1_PORT_16A, XS1_PORT_1B, XS1_PORT_1G, XS1_PORT_1C, XS1_PORT_1F, XS1_CLKBLK_2 };

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
        image_sensor_get_frame(c_img, c_dc, frBuf[frBufIndex], LCD_HEIGHT, LCD_WIDTH);

        display_controller_frame_buffer_commit(c_dc, frBuf[frBufIndex]);
        delay_milliseconds(10);   // To remove flicker

    }
}
/********************************************************************************************
 * As per datasheet (Page No. 49,Figure 18) slave mode operation is carried out based on the
 * clock cycles at which the input pins of the sensor is triggered.
 * Pins used : EXPOSURE, STFRM_OUT, STLN_OUT
 * As mentioned in datasheet Vertical Blank (context A) is set to 4.
 * STLN_OUT is maintained as much as near to LINE_VALID values.i.e similary to it.
 * EXPOSURE : |```````````````|___________________________________________
 * STFRM_OUT: ______________________________|````````````````|___________
 * STLN_OUT : ________________________________________|``````````````|__|``````````````|__|```
 *
 *          : |<------- Integration Time --------->|<------- Vertical Blanking --------- >|
 * ---------------------------------------------------------------------------------------- *
 * Pixel Integration Control (Page No. 52)
 * Total Integration Time = (No. of rows of integration x row time) +
 *                          (No. of pixels of integration x pixel time)
 * No. of rows of integration = R0x0B => Coarse Shutter Width 1 Context A = 480
 * No. of pixels of Integration = R0xD5 => Fine Shutter Width Total Context A = 0
 * Row Timing = (R0x04 + R0x05) master clock periods = (480 + 220) = 700 master clock periods
 * pixel time = pixel clock = 25MHz = 40nSec
 * Integration Time = (480 x 846) + (0 x 40nSec) = (406080) master clock period = 16243.2uSec
 * ---------------------------------------------------------------------------------------- *
 * STLN_OUT time is approximately equal to LINE_VALID time (Page No. 13, Figure 8, Table 4)
 * Row Timing = (R0x04 + R0x05) master clock periods = (752 + 94) = 846 master clock periods
 * Active data time (ON Time) = 752 pixel clocks = 30.08uSec = 3008 ticks
 * Horizontal blanking (OFF Time) = 94 pixel clocks = 3.76uSec = 376 ticks
 * ---------------------------------------------------------------------------------------- *
 * Consider EXPOSURE Time (half of Integration Time) = (16243.2/2) = 8121.6uSec = 812160 ticks
 * Assuimng STFRM_OUT Time as 25% Integration Time = (16243.2x0.25) = 4060.8uSec = 406080 ticks
 *******************************************************************************************/
void slave_port_trigger(img_snsr_slave_mode_ports &imgports_slave,streaming chanend c_img_slv)
{
    timer slv_tmr;
    unsigned tick = 0;
    unsigned guard_flag = 0;

    while(1) {
      select {
        case c_img_slv :> unsigned cmd: {
          guard_flag = 0;

          imgports_slave.exposure  <: 0;
          imgports_slave.stfrm_out <: 0;
          imgports_slave.stln_out  <: 0;
          if(cmd == 1) {
            imgports_slave.exposure  <: 1;

            slv_tmr :> tick;
            slv_tmr when timerafter(tick+812160) :> tick;        //812160

            imgports_slave.exposure  <: 0;
            slv_tmr when timerafter(tick+609120) :> tick;        //609120

            imgports_slave.stfrm_out <: 1;
            slv_tmr when timerafter(tick+404576) :> tick;        //404670

            imgports_slave.stln_out  <: 1; // vertical blanking period
            slv_tmr when timerafter(tick+1504) :> tick;           //1504

            imgports_slave.stfrm_out <: 0;
            slv_tmr when timerafter(tick+1504) :> tick;           //1410 //960

            imgports_slave.stln_out  <: 0;
            slv_tmr when timerafter(tick+376) :> tick;           //352 //880

            imgports_slave.stln_out  <: 1;
            slv_tmr when timerafter(tick+3008) :> tick;          //2820 //1920

            imgports_slave.stln_out  <: 0;
            slv_tmr when timerafter(tick+376) :> tick;           //342 //870

            c_img_slv <: 1; //ack
            guard_flag = 1;
          }
          }
          break;

          (guard_flag) => default: {
              slv_tmr :> tick;
              imgports_slave.stln_out <: 1;
              slv_tmr when timerafter(tick+3008) :> tick;         //2820 //1920
              imgports_slave.stln_out <: 0;
              slv_tmr when timerafter(tick+376) :> tick;          //352 //880

          }
          break;
      }
    }
}

int main(){
    chan c_dc, c_lcd, c_sdram;
    streaming chan c_img_sen, c_img_slv;

    par{
        on tile[1]: image_sensor_server(imgports, c_img_sen,c_img_slv,SLAVE_MODE);
        on tile[1]: slave_port_trigger(imgports_slave,c_img_slv);  // TODO: Merge it with
        on tile[0]: app(c_img_sen,c_dc);
        on tile[0]: display_controller(c_dc,c_lcd,c_sdram);
        on tile[0]: lcd_server(c_lcd,lcdports);
        on tile[0]: sdram_server(c_sdram,sdramports);

/*
        on tile[0]: par(int i=0;i<2;i++)
                        while (1) {
                          set_core_fast_mode_on();
                        }
        on tile[1]: par(int i=0;i<7;i++)
                        while (1) {
                          set_core_fast_mode_on();
                        }
*/
    }

    return 0;
}
