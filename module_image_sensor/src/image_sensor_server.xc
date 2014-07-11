#include <xs1.h>
#include <timer.h>
#include <print.h>
#include <platform.h>

#include "image_sensor.h"
#include "image_sensor_defines.h"
#include "i2c.h"


static inline void config_data_port(struct image_sensor_ports &imgports,image_sensor_opt_modes_t mode){

    configure_clock_src(imgports.clk1, imgports.pix_clk);   // Port clock setup
    if(mode == SLAVE_MODE) {
      configure_in_port(imgports.data_port,imgports.clk1);
      configure_in_port(imgports.line_valid,imgports.clk1);
    }else if(mode == MASTER_MODE)
      configure_in_port_strobed_slave(imgports.data_port, imgports.line_valid, imgports.clk1);

    start_clock(imgports.clk1);

}

static void init_registers(struct image_sensor_ports &imgports, image_sensor_opt_modes_t mode){
    unsigned char i2c_data[2];

    i2c_master_read_reg(DEV_ADDR, CHIP_VERSION_REG, i2c_data, 2, imgports.i2c_ports);
    delay_milliseconds(1);
    printstr("Image Sensor Chip Version : ");
    printhex(i2c_data[0]);
    printhexln(i2c_data[1]);

    i2c_master_read_reg(DEV_ADDR, RESET_REG, i2c_data, 2, imgports.i2c_ports);
    i2c_data[1] |= 0x03;
    i2c_master_write_reg(DEV_ADDR, RESET_REG, i2c_data, 2, imgports.i2c_ports);
    delay_milliseconds(1);

    i2c_data[0] = 0;
    i2c_data[1] = AEC | (AGC<<1);
    i2c_master_write_reg(DEV_ADDR, AEC_AGC_ENABLE_REG, i2c_data, 2, imgports.i2c_ports);
    delay_milliseconds(1);

    for (unsigned reg = DIG_GAIN_REG_START; reg <= DIG_GAIN_REG_END; reg++){
        i2c_master_read_reg(DEV_ADDR, reg, i2c_data, 2, imgports.i2c_ports);
        delay_milliseconds(1);
        i2c_data[1] &= 0b11110000;
        i2c_data[1] |= DIG_GAIN;
        i2c_master_write_reg(DEV_ADDR, reg, i2c_data, 2, imgports.i2c_ports);
        delay_milliseconds(1);
    }

    i2c_master_read_reg(DEV_ADDR, CHIP_CNTL_REG, i2c_data, 2, imgports.i2c_ports);
    delay_milliseconds(1);
    if(mode == SLAVE_MODE) {
        i2c_data[1] &= 0b11100111;  // Clearing bit [4:3] for slave mode operation
    }
    else if (mode == SNAPSHOT_MODE) {
        i2c_data[1] &= 0b11100111;  // Clearing bit [4:3]
        i2c_data[1] |= 0b00011000;  // Clearing bit [4:3] for snapshot mode
    }
    else // master mode
    {
        // do nothing. by default sensor is in master mode...
    }
    i2c_data[0] &= 0b11111101;  // Clearing bit 9 for normal operation
    i2c_master_write_reg(DEV_ADDR, CHIP_CNTL_REG, i2c_data, 2, imgports.i2c_ports);
    delay_milliseconds(1);

    if(mode == SLAVE_MODE) {
        i2c_master_read_reg(DEV_ADDR, VER_BLANK_REG, i2c_data, 2, imgports.i2c_ports);
        delay_milliseconds(1);
        i2c_data[0] = 0;
        i2c_data[1] = 4;
        i2c_master_write_reg(DEV_ADDR, VER_BLANK_REG, i2c_data, 2, imgports.i2c_ports);
        delay_milliseconds(1);
    }
}


static void config_registers(struct image_sensor_ports &imgports, unsigned height, unsigned width){
    unsigned char i2c_data[2];
    unsigned horBlank, rowStart, colStart;

    i2c_data[0] = height >> 8; // MS byte of height
    i2c_data[1] = height & 0xff; // LS byte
    i2c_master_write_reg(DEV_ADDR, WIN_HEIGHT_REG, i2c_data, 2, imgports.i2c_ports);
    delay_milliseconds(1);


    i2c_data[0] = width >> 8; // MS byte of width
    i2c_data[1] = width & 0xff; // LS byte
    i2c_master_write_reg(DEV_ADDR, WIN_WIDTH_REG, i2c_data, 2, imgports.i2c_ports);
    delay_milliseconds(1);

    // Total row time should be 690 cols for correct operation of ADC. If not, add horizontal blanking pulses.
    if (width<700) {
        horBlank = 700-width;
        if (horBlank<94) horBlank = 94; //Default is 94

        i2c_data[0] = horBlank >> 8; // MS byte of width
        i2c_data[1] = horBlank & 0xff; // LS byte
        i2c_master_write_reg(DEV_ADDR, HOR_BLANK_REG, i2c_data, 2, imgports.i2c_ports);
    }

    // Align the capture window to the center of sensor's resolution
    rowStart = (MAX_HEIGHT-height)/2;
    colStart = (MAX_WIDTH-width)/2;

    i2c_data[0] = rowStart >> 8; // MS byte of row start
    i2c_data[1] = rowStart & 0xff; // LS byte
    i2c_master_write_reg(DEV_ADDR, ROW_START_REG, i2c_data, 2, imgports.i2c_ports);
    delay_milliseconds(1);

    i2c_data[0] = colStart >> 8; // MS byte of col start
    i2c_data[1] = colStart & 0xff; // LS byte
    i2c_master_write_reg(DEV_ADDR, COL_START_REG, i2c_data, 2, imgports.i2c_ports);
    delay_milliseconds(1);

}


static inline unsigned do_input(in buffered port:32 data_port) {
  unsigned data;
  asm volatile("in %0, res[%1]":"=r"(data):"r"(data_port));
  return data;
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
void trigger_exposure_stfrm_out(img_snsr_slave_mode_ports &imgports_slave)
{
    timer slv_tmr;
    unsigned tick = 0;

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

    slv_tmr when timerafter(tick+880) :> tick;           //352 //880
    for(int i = 0; i < 5; i++) {
      imgports_slave.stln_out  <: 1;
      slv_tmr when timerafter(tick+3008) :> tick;          //2820 //1920

      imgports_slave.stln_out  <: 0;
      slv_tmr when timerafter(tick+880) :> tick;           //352 //880
    }
}
void image_sensor_server(struct image_sensor_ports &imgports, img_snsr_slave_mode_ports &imgports_slave,
                         streaming chanend c_imgSensor,image_sensor_opt_modes_t mode)
{
    unsigned cmd;
    unsigned height, width;
    unsigned n_data = 0;

    // Initialization
    if(mode == SLAVE_MODE)
      configure_out_port(imgports_slave.stln_out, imgports.clk1,0);

    config_data_port(imgports,mode);
    i2c_master_init(imgports.i2c_ports);
    init_registers(imgports,mode);


    /* Wait for configuration data to be received from client */
    c_imgSensor :> cmd;
    c_imgSensor :> height;
    c_imgSensor :> width;
    config_registers(imgports,height,width);

    while(1) {
      c_imgSensor :> cmd;
      if(mode == SLAVE_MODE) {
        clearbuf(imgports.data_port);
        trigger_exposure_stfrm_out(imgports_slave);

        for(unsigned l=0; l<height; l++) {
          imgports_slave.stln_out <: 1;
          delay_microseconds(9);
          for (unsigned i=0; i<width/4; i++) {
            unsigned data = do_input(imgports.data_port);
            c_imgSensor <: data;
          }
          imgports_slave.stln_out <: 0;
          delay_microseconds(22);
        }
        imgports_slave.stln_out <: 0;
      }
      else // master mode
      {
        n_data = (height*width)/4;
        unsigned i=0;

        imgports.frame_valid when pinseq(0) :> void;
        imgports.frame_valid when pinseq(1) :> void; // wait for a valid frame

        clearbuf(imgports.data_port);
        for (; i<n_data; i++){
          unsigned data = do_input(imgports.data_port);
          c_imgSensor <: data;
        }
      }
    }
}
