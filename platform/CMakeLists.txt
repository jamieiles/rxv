add_custom_command(OUTPUT rxv-arty.dtb
		   COMMAND dtc -I dts ${CMAKE_CURRENT_SOURCE_DIR}/rxv-arty.dts -O dtb -o ${CMAKE_CURRENT_BINARY_DIR}/rxv-arty.dtb
		   DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/rxv-arty.dts)
add_custom_command(OUTPUT rxv-arty-ramdisk.dtb
		   COMMAND dtc -I dts ${CMAKE_CURRENT_SOURCE_DIR}/rxv-arty-ramdisk.dts -O dtb -o ${CMAKE_CURRENT_BINARY_DIR}/rxv-arty-ramdisk.dtb
		   DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/rxv-arty-ramdisk.dts
			   ${CMAKE_CURRENT_SOURCE_DIR}/rxv-arty.dts)
add_custom_command(OUTPUT rxv-arty-nonet.dtb
		   COMMAND dtc -I dts ${CMAKE_CURRENT_SOURCE_DIR}/rxv-arty-nonet.dts -O dtb -o ${CMAKE_CURRENT_BINARY_DIR}/rxv-arty-nonet.dtb
		   DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/rxv-arty-nonet.dts
			   ${CMAKE_CURRENT_SOURCE_DIR}/rxv-arty.dts)
add_custom_command(OUTPUT rxv-emul.dtb
		   COMMAND dtc -I dts ${CMAKE_CURRENT_SOURCE_DIR}/rxv-emul.dts -O dtb -o ${CMAKE_CURRENT_BINARY_DIR}/rxv-emul.dtb
		   DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/rxv-emul.dts)
add_custom_target(dtbs ALL
		  DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/rxv-emul.dtb
		  ${CMAKE_CURRENT_BINARY_DIR}/rxv-arty.dtb
		  ${CMAKE_CURRENT_BINARY_DIR}/rxv-arty-nonet.dtb
		  ${CMAKE_CURRENT_BINARY_DIR}/rxv-arty-ramdisk.dtb)
