// Apple silicon's private I2C access to external screens (IOKit), as m1ddc and MonitorControl use it,
// for DDC/CI: the monitor's own controls (brightness) over the video cable. display.sh compiles it with display_helper.swift.
#import <IOKit/IOKitLib.h>
typedef CFTypeRef IOAVServiceRef;
extern IOAVServiceRef IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
extern IOReturn IOAVServiceReadI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t offset, void *outputBuffer, uint32_t outputBufferSize);
extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t dataAddress, void *inputBuffer, uint32_t inputBufferSize);
