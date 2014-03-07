#include <stdint.h>

#include "image_sensor.h"
#include "image_sensor_defines.h"
#include "display_controller.h"


void image_sensor_set_capture_window(streaming chanend c_imgSensor, unsigned height, unsigned width){
    c_imgSensor <: (unsigned)CONFIG;
    c_imgSensor <: height;
    c_imgSensor <: width;
}


#pragma unsafe arrays
inline unsafe void get_row(streaming chanend c, unsigned * unsafe dataPtr, unsigned width){
    unsigned n_data = width/2;
    for (unsigned i=0; i<n_data; i++){
        c :> *(dataPtr++);
    }
}


#pragma unsafe arrays
inline unsafe void store_row (chanend c_dc, unsigned row, unsigned frBuf, intptr_t buf){
    display_controller_image_write_line_p(c_dc, row, frBuf, buf);
    display_controller_wait_until_idle_p(c_dc, buf);
}


inline unsigned short rgb888_to_rgb565(char b, char g, char r) {
  return (unsigned short)((r >> 3) & 0x1F) | ((unsigned short)((g >> 2) & 0x3F) << 5) | ((unsigned short)((b >> 3) & 0x1F) << 11);
}

#pragma unsafe arrays
void color_interpolation(chanend c_dc, unsigned frBuf, unsigned height, unsigned width){
    unsigned buf[3][MAX_WIDTH/2], rgb565[MAX_WIDTH/2];
    char r[MAX_WIDTH], g[MAX_WIDTH], b[MAX_WIDTH];

    // Read first two rows
    display_controller_image_read_line(c_dc, 0, frBuf, buf[0]);
    display_controller_wait_until_idle(c_dc, buf[0]);
    display_controller_image_read_line(c_dc, 1, frBuf, buf[1]);
    display_controller_wait_until_idle(c_dc, buf[1]);

    // Store first and last rows with 0s
    for (unsigned j=0; j<width/2; j++)
        rgb565[j]=0;
    display_controller_image_write_line(c_dc, 0, frBuf, rgb565);
    display_controller_wait_until_idle(c_dc, rgb565);
    display_controller_image_write_line(c_dc, height-1, frBuf, rgb565);
    display_controller_wait_until_idle(c_dc, rgb565);


    // Find missing color components
    for (unsigned i=2; i<height; i++){
        unsigned row = i-1;

        display_controller_image_read_line(c_dc, i, frBuf, buf[i%3]);
        display_controller_wait_until_idle(c_dc, buf[i%3]);

        if (row&1){
            for (unsigned j=1; j<width-1; j+=2){    // odd row, odd col, green pix
                g[j] = ((buf[row%3],short[])[j])>>2 & 0xff;
                unsigned b_top = ((buf[(row-1)%3],short[])[j]) & 0x3ff;
                unsigned b_bot = ((buf[(row+1)%3],short[])[j]) & 0x3ff;
                b[j] = (b_top+b_bot)>>3; // div 2 for averaging, div 4 for 10 to 8-bit conversion
                unsigned r_left = ((buf[row%3],short[])[j-1]) & 0x3ff;
                unsigned r_right = ((buf[row%3],short[])[j+1]) & 0x3ff;
                r[j] = (r_left+r_right)>>3;
            }
            for (unsigned j=2; j<width-1; j+=2){    // odd row, even col, red pix
                r[j] = ((buf[row%3],short[])[j])>>2 & 0xff;
                unsigned b_diag1 = ((buf[(row-1)%3],short[])[j-1]) & 0x3ff;
                unsigned b_diag2 = ((buf[(row-1)%3],short[])[j+1]) & 0x3ff;
                unsigned b_diag3 = ((buf[(row+1)%3],short[])[j-1]) & 0x3ff;
                unsigned b_diag4 = ((buf[(row+1)%3],short[])[j+1]) & 0x3ff;
                b[j] = (b_diag1+b_diag2+b_diag3+b_diag4)>>4; // div 4 for averaging, div 4 for 10 to 8-bit conversion
                unsigned g_adj1 = ((buf[(row-1)%3],short[])[j]) & 0x3ff;
                unsigned g_adj2 = ((buf[(row+1)%3],short[])[j]) & 0x3ff;
                unsigned g_adj3 = ((buf[row%3],short[])[j-1]) & 0x3ff;
                unsigned g_adj4 = ((buf[row%3],short[])[j+1]) & 0x3ff;
                g[j] = (g_adj1+g_adj2+g_adj3+g_adj4)>>4;
            }
        }
        else {
            for (unsigned j=1; j<width-1; j+=2){    // even row, odd col, blue pix
                b[j] = ((buf[row%3],short[])[j])>>2 & 0xff;
                unsigned r_diag1 = ((buf[(row-1)%3],short[])[j-1]) & 0x3ff;
                unsigned r_diag2 = ((buf[(row-1)%3],short[])[j+1]) & 0x3ff;
                unsigned r_diag3 = ((buf[(row+1)%3],short[])[j-1]) & 0x3ff;
                unsigned r_diag4 = ((buf[(row+1)%3],short[])[j+1]) & 0x3ff;
                r[j] = (r_diag1+r_diag2+r_diag3+r_diag4)>>4;
                unsigned g_adj1 = ((buf[(row-1)%3],short[])[j]) & 0x3ff;
                unsigned g_adj2 = ((buf[(row+1)%3],short[])[j]) & 0x3ff;
                unsigned g_adj3 = ((buf[row%3],short[])[j-1]) & 0x3ff;
                unsigned g_adj4 = ((buf[row%3],short[])[j+1]) & 0x3ff;
                g[j] = (g_adj1+g_adj2+g_adj3+g_adj4)>>4;
            }
            for (unsigned j=2; j<width-1; j+=2){    // even row, even col, green pix
                g[j] = ((buf[row%3],short[])[j])>>2 & 0xff;
                unsigned b_left = ((buf[row%3],short[])[j-1]) & 0x3ff;
                unsigned b_right = ((buf[row%3],short[])[j+1]) & 0x3ff;
                b[j] = (b_left+b_right)>>3;
                unsigned r_top = ((buf[(row-1)%3],short[])[j]) & 0x3ff;
                unsigned r_bot = ((buf[(row+1)%3],short[])[j]) & 0x3ff;
                r[j] = (r_top+r_bot)>>3;
            }
        }

        // RGB565 conversion and write row
        for (unsigned j=1; j<width-1; j++)
            (rgb565,unsigned short[])[j] = rgb888_to_rgb565(b[j], g[j], r[j]);

        (rgb565,unsigned short[])[0] = 0;
        (rgb565,unsigned short[])[width-1] = 0;

        display_controller_image_write_line(c_dc, row, frBuf, rgb565);
        display_controller_wait_until_idle(c_dc, rgb565);
    }

}


#pragma unsafe arrays
void image_sensor_get_frame(streaming chanend c_imgSensor, chanend c_dispCont, unsigned frBuf, unsigned height, unsigned width){
    unsigned data1[MAX_WIDTH/2], data2[MAX_WIDTH/2];
    unsigned * unsafe tempPtr, * unsafe readBufPtr, * unsafe storeBufPtr;

    c_imgSensor <: (unsigned)GET_FRAME;

    // Get frame & store
    unsafe {
        readBufPtr = data1; storeBufPtr = data2;    // pointers to manage double buffer
        get_row (c_imgSensor,readBufPtr,width);

        for (unsigned r=1; r<height; r++){
            //swap data buffers for reading and storing
            tempPtr = readBufPtr;
            readBufPtr = storeBufPtr;
            storeBufPtr = tempPtr;

            par {
                get_row (c_imgSensor,readBufPtr,width);
                store_row(c_dispCont,r-1,frBuf,(intptr_t)storeBufPtr);
            }
        }

        store_row(c_dispCont,height-1,frBuf,(intptr_t)readBufPtr);
    }

    // Color interpolation
    color_interpolation(c_dispCont, frBuf, height, width);

}



