
#ifndef IMAGE_SENSOR_DEFINES_H_
#define IMAGE_SENSOR_DEFINES_H_

enum commands {CONFIG, GET_FRAME};

// Sensor registers
#define DEV_ADDR 0x48   // Seven most significant bits of 0x90 and 0x91
#define RESET_REG 0x0C
#define CHIP_CNTL_REG 0x07
#define WIN_HEIGHT_REG 0x03
#define WIN_WIDTH_REG 0x04
#define HOR_BLANK_REG 0x05
#define ROW_START_REG 0x02
#define COL_START_REG 0x01

// Registers for performance (video quality) tuning
#define GREEN_REDUCTION_FACTOR_NUM 8     // Numerator of the factor for white balancing
#define GREEN_REDUCTION_FACTOR_DEN 10     // Denominator of the factor for white balancing

#define AEC_AGC_ENABLE_REG 0xAF
#define AEC 0
#define AGC 0   // Disable AGC in sunlight. Enable AGC in artificial light and adjust DIG_GAIN.

#define DIG_GAIN_REG_START 0x80
#define DIG_GAIN_REG_END 0x98
#define DIG_GAIN 10  //Range is 1-15. Default is 4. Increase it in a darker environment.


// Sensor resolution
#define MAX_HEIGHT 480
#define MAX_WIDTH 752



#endif /* IMAGE_SENSOR_DEFINES_H_ */
