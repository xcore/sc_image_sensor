#include <timer.h>

#include "image_sensor.h"
#include "image_sensor_defines.h"
#include "i2c.h"

static inline void config_data_port(struct image_sensor_ports &imgports){

    configure_clock_src(imgports.clk1, imgports.pix_clk);   // Port clock setup
    configure_in_port_strobed_slave(imgports.data_port, imgports.line_valid, imgports.clk1);
    start_clock(imgports.clk1);

}

static void init_registers(struct image_sensor_ports &imgports){
    unsigned char i2c_data[2];

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
    i2c_data[0] &= 0b11111101;  // Clearing bit 9 for normal operation
    i2c_master_write_reg(DEV_ADDR, CHIP_CNTL_REG, i2c_data, 2, imgports.i2c_ports);
    delay_milliseconds(1);

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


void image_sensor_server(struct image_sensor_ports &imgports, streaming chanend c_imgSensor){
    unsigned cmd;
    unsigned height, width;

    // Initialization
    config_data_port(imgports);
    i2c_master_init(imgports.i2c_ports);
    init_registers(imgports);

    while (1){

        c_imgSensor :> cmd;

        if (cmd==CONFIG) {

                c_imgSensor :> height;
                c_imgSensor :> width;

                config_registers(imgports,height,width);

        } else {

                unsigned n_data = height*width/4;
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
