#include <stdint.h>

#include "image_sensor.h"
#include "image_sensor_defines.h"
#include "sdram.h"

void image_sensor_set_capture_window(streaming chanend c_imgSensor, unsigned height, unsigned width){
    c_imgSensor <: (unsigned)CONFIG;
    c_imgSensor <: height;
    c_imgSensor <: width;
}


#pragma unsafe arrays
inline unsafe void get_row(streaming chanend c, unsigned * unsafe dataPtr, unsigned width){
    unsigned n_data = width/4;
    for (unsigned i=0; i<n_data; i++){
        c :> *(dataPtr++);
    }
}


#pragma unsafe arrays
inline unsafe void store_row (chanend c_sdram, unsigned row, unsigned width, unsigned SDRAMfrBufBank, unsigned SDRAMfrBufRow, intptr_t buf){
    unsigned widthWords = width/2;
    unsigned rowIncrement = (width/SDRAM_COL_COUNT)+1;
    unsigned startRow = SDRAMfrBufRow + row*rowIncrement;
    sdram_buffer_write_p(c_sdram, SDRAMfrBufBank, startRow, 0, widthWords, buf);
    sdram_wait_until_idle_p(c_sdram,buf);
}


inline unsigned short rgb888_to_rgb565(char b, char g, char r) {
  return (unsigned short)((r >> 3) & 0x1F) | ((unsigned short)((g >> 2) & 0x3F) << 5) | ((unsigned short)((b >> 3) & 0x1F) << 11);
}

#pragma unsafe arrays
void color_interpolation(chanend c_sdram, unsigned SDRAMfrBufBank, unsigned SDRAMfrBufRow, unsigned height, unsigned width){
    unsigned buf[3][MAX_WIDTH/2], rgb565[MAX_WIDTH/2];
    char r[MAX_WIDTH], g[MAX_WIDTH], b[MAX_WIDTH];
    intptr_t bufferPtr;
    unsigned startRow;

    unsigned widthWords = width/2;
    unsigned rowIncrement = (width/SDRAM_COL_COUNT)+1;

    // Read first two rows
    asm("mov %0, %1" : "=r"(bufferPtr) : "r"(buf[0]));
    startRow = SDRAMfrBufRow;
    sdram_buffer_read_p(c_sdram, SDRAMfrBufBank, startRow, 0, widthWords, bufferPtr);
    sdram_wait_until_idle_p(c_sdram,bufferPtr);

    asm("mov %0, %1" : "=r"(bufferPtr) : "r"(buf[1]));
    startRow = SDRAMfrBufRow + rowIncrement;
    sdram_buffer_read_p(c_sdram, SDRAMfrBufBank, startRow, 0, widthWords, bufferPtr);
    sdram_wait_until_idle_p(c_sdram,bufferPtr);

    // Store first and last rows with 0s
    for (unsigned j=0; j<width/2; j++)
        rgb565[j]=0;

    asm("mov %0, %1" : "=r"(bufferPtr) : "r"(rgb565));
    startRow = SDRAMfrBufRow;
    sdram_buffer_write_p(c_sdram, SDRAMfrBufBank, startRow, 0, widthWords, bufferPtr);
    sdram_wait_until_idle_p(c_sdram,bufferPtr);

    asm("mov %0, %1" : "=r"(bufferPtr) : "r"(rgb565));
    startRow = SDRAMfrBufRow + (height-1)*rowIncrement;
    sdram_buffer_write_p(c_sdram, SDRAMfrBufBank, startRow, 0, widthWords, bufferPtr);
    sdram_wait_until_idle_p(c_sdram,bufferPtr);


    // Find missing color components
    for (unsigned i=2; i<height; i++){
        unsigned row = i-1;

        asm("mov %0, %1" : "=r"(bufferPtr) : "r"(buf[i%3]));
        unsigned startRow = SDRAMfrBufRow + i*rowIncrement;
        sdram_buffer_read_p(c_sdram, SDRAMfrBufBank, startRow, 0, widthWords, bufferPtr);
        sdram_wait_until_idle_p(c_sdram,bufferPtr);

        if (row&1){
            for (unsigned j=1; j<width-1; j+=2){    // odd row, odd col, green pix
                g[j] = (buf[row%3],char[])[j];
                unsigned b_top = (buf[(row-1)%3],char[])[j];
                unsigned b_bot = (buf[(row+1)%3],char[])[j];
                b[j] = (b_top+b_bot)/2; // Take average
                unsigned r_left = (buf[row%3],char[])[j-1];
                unsigned r_right = (buf[row%3],char[])[j+1];
                r[j] = (r_left+r_right)/2;
            }
            for (unsigned j=2; j<width-1; j+=2){    // odd row, even col, red pix
                r[j] = (buf[row%3],char[])[j];
                unsigned b_diag1 = (buf[(row-1)%3],char[])[j-1];
                unsigned b_diag2 = (buf[(row-1)%3],char[])[j+1];
                unsigned b_diag3 = (buf[(row+1)%3],char[])[j-1];
                unsigned b_diag4 = (buf[(row+1)%3],char[])[j+1];
                b[j] = (b_diag1+b_diag2+b_diag3+b_diag4)/4;
                unsigned g_adj1 = (buf[(row-1)%3],char[])[j];
                unsigned g_adj2 = (buf[(row+1)%3],char[])[j];
                unsigned g_adj3 = (buf[row%3],char[])[j-1];
                unsigned g_adj4 = (buf[row%3],char[])[j+1];
                g[j] = (g_adj1+g_adj2+g_adj3+g_adj4)/4;
            }
        }
        else {
            for (unsigned j=1; j<width-1; j+=2){    // even row, odd col, blue pix
                b[j] = (buf[row%3],char[])[j];
                unsigned r_diag1 = (buf[(row-1)%3],char[])[j-1];
                unsigned r_diag2 = (buf[(row-1)%3],char[])[j+1];
                unsigned r_diag3 = (buf[(row+1)%3],char[])[j-1];
                unsigned r_diag4 = (buf[(row+1)%3],char[])[j+1];
                r[j] = (r_diag1+r_diag2+r_diag3+r_diag4)/4;
                unsigned g_adj1 = (buf[(row-1)%3],char[])[j];
                unsigned g_adj2 = (buf[(row+1)%3],char[])[j];
                unsigned g_adj3 = (buf[row%3],char[])[j-1];
                unsigned g_adj4 = (buf[row%3],char[])[j+1];
                g[j] = (g_adj1+g_adj2+g_adj3+g_adj4)/4;
            }
            for (unsigned j=2; j<width-1; j+=2){    // even row, even col, green pix
                g[j] = (buf[row%3],char[])[j];
                unsigned b_left = (buf[row%3],char[])[j-1];
                unsigned b_right = (buf[row%3],char[])[j+1];
                b[j] = (b_left+b_right)/2;
                unsigned r_top = (buf[(row-1)%3],char[])[j];
                unsigned r_bot = (buf[(row+1)%3],char[])[j];
                r[j] = (r_top+r_bot)/2;
            }
        }


        // RGB565 conversion and write row
        for (unsigned j=1; j<width-1; j++)
            (rgb565,unsigned short[])[j] = rgb888_to_rgb565(b[j], g[j]*GREEN_REDUCTION_FACTOR_NUM/GREEN_REDUCTION_FACTOR_DEN, r[j]);     // 8/10 is for white balancing since the output looks greenish

        (rgb565,unsigned short[])[0] = 0;
        (rgb565,unsigned short[])[width-1] = 0;

        asm("mov %0, %1" : "=r"(bufferPtr) : "r"(rgb565));
        sdram_buffer_write_p(c_sdram, SDRAMfrBufBank, startRow-rowIncrement, 0, widthWords, bufferPtr);
        sdram_wait_until_idle_p(c_sdram,bufferPtr);

    }

}


#pragma unsafe arrays
void image_sensor_get_frame(streaming chanend c_imgSensor, chanend c_sdram, unsigned SDRAMfrBufBank, unsigned SDRAMfrBufRow, unsigned height, unsigned width){
    unsigned data1[MAX_WIDTH/4], data2[MAX_WIDTH/4];
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
                store_row(c_sdram,r-1,width,SDRAMfrBufBank,SDRAMfrBufRow,(intptr_t)storeBufPtr);
            }
        }

        store_row(c_sdram,height-1,width,SDRAMfrBufBank,SDRAMfrBufRow,(intptr_t)readBufPtr);
    }

    // Color interpolation
    color_interpolation(c_sdram, SDRAMfrBufBank, SDRAMfrBufRow, height, width);

}



