Image Sensor Board Design Options
==================================

.. note:: This design options are just proposals given during the initial board design stage for ``VISION PROJECT``, were there was an pinout constraints on xCORE IO's. 

Option 1
--------

.. list-table::
 :header-rows: 1

 * - Component
   - Lines Description
   - NOL
   - Remarks
 * - SDRAM
   - Address & Data Lines
   - 16
   - 
 * - SDRAM
   - Control Lines
   - 3
   - 
 * - SDRAM
   - Clock
   - 1
   - This clock can be buffered & given to image sensor
 * - Image Sensor
   - Data Lines
   - 8
   - 
 * - Image Sensor
   - Pixel Clock
   - 1
   -
 * - Image Sensor
   - System Clock
   - 0
   - SDRAM clock can be given to this pin
 * - Image Sensor
   - LINE_VALID
   - 1
   - 
 * - MUX
   - I2C_SCL
   - 1
   - EXPOSURE line muxed with I2C_SCL
 * - MUX
   - I2C_SDA
   - 1
   - STLN_OUT line muxed with I2C_SDA
 * - MUX
   - FRAME_VALID
   - 1
   - STFRM_OUT line muxed with FRAME_VALID
 * - MUX
   - Mux Selection
   - 1
   - Along with xCORE User LED pin
 * - Total Pin Usage
   -
   - 34
   -

- NOL: Number of Lines

Option 2
--------

.. list-table::
 :header-rows: 1

 * - Component
   - Lines Description
   - NOL
   - Remarks
 * - SDRAM
   - Address & Data Lines
   - 16
   - 
 * - SDRAM
   - Control Lines
   - 3
   - 
 * - SDRAM
   - Clock
   - 0
   - Use on-board crystal or I2C based clock generator
 * - Image Sensor
   - Data Lines
   - 8
   - 
 * - Image Sensor
   - Pixel Clock
   - 1
   -
 * - Image Sensor
   - System Clock
   - 0
   - Use on-board crystal or I2C based clock generator
 * - Image Sensor
   - LINE_VALID
   - 1
   - 
 * - MUX
   - I2C_SCL
   - 1
   - EXPOSURE line muxed with I2C_SCL
 * - MUX
   - I2C_SDA
   - 1
   - STLN_OUT line muxed with I2C_SDA
 * - MUX
   - FRAME_VALID
   - 1
   - STFRM_OUT line muxed with FRAME_VALID
 * - MUX
   - Mux Selection
   - 1
   - xCORE User LED pin can be left free
 * - Total Pin Usage
   -
   - 33
   -

Option 3
--------

.. list-table::
 :header-rows: 1

 * - Component
   - Lines Description
   - NOL
   - Remarks
 * - SDRAM
   - Address & Data Lines
   - 16
   - 
 * - SDRAM
   - Control Lines
   - 3
   - 
 * - SDRAM
   - Clock
   - 0
   - Use on-board crystal or I2C based clock generator
 * - Image Sensor
   - Data Lines
   - 8
   - 
 * - Image Sensor
   - Pixel Clock
   - 1
   -
 * - Image Sensor
   - System Clock
   - 1
   - In case, if we want to change the image sensor clock-in
 * - Image Sensor
   - LINE_VALID
   - 1
   - 
 * - MUX
   - I2C_SCL
   - 1
   - EXPOSURE line muxed with I2C_SCL
 * - MUX
   - I2C_SDA
   - 1
   - STLN_OUT line muxed with I2C_SDA
 * - MUX
   - FRAME_VALID
   - 1
   - STFRM_OUT line muxed with FRAME_VALID
 * - MUX
   - Mux Selection
   - 1
   - Along with xCORE User LED pin
 * - Total Pin Usage
   -
   - 34
   -

Left out Pins
-------------
.. note:: Some of the pins are not considered above, based on the test results.

#. LED_OUT: There is no much practical usage of this pin.
#. FRAME_VALID (in Slave mode): As per the timing diagram, FRAME_VALID is not required on slave mode(Refer: Figure.18). Also, as per the current development code, LINE_VALID is configured as strobed buffered port. All the data readout happens based on LINE_VALID and not FRAME_VALID.
#. DOUT[1:0]: Low resolution pins are ignored inorder to sample data from sensor as 8-bit format. This is because of acquiring 8-bit data and processing was much more faster while using 8-bit port compared to 10-bit data processing from 16-bit port.
