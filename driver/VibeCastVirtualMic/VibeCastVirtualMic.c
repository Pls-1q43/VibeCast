#include <CoreAudio/AudioHardware.h>
#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <string.h>

#define kObjectDevice 2
#define kObjectInputStream 3
#define kObjectOutputStream 4
#define kSampleRate 48000.0
#define kChannels 2
#define kRingFrames (48000 * 12)
#define kZeroTimeStampPeriod 48000
#define kDeviceUID "com.vibecast.virtualmic.device"
#define kModelUID "com.vibecast.virtualmic.model"

static AudioServerPlugInDriverInterface gDriverInterface;
static AudioServerPlugInDriverInterface* gDriverInterfacePtr = &gDriverInterface;
static AudioServerPlugInHostRef gHost = NULL;
static _Atomic UInt32 gRefCount = 1;
static _Atomic UInt32 gRunningClients = 0;
static _Atomic UInt64 gWriteFrame = 0;
static _Atomic UInt64 gReadFrame = 0;
static Float32 gRing[kRingFrames * kChannels];
static UInt64 gStartHostTime = 0;
static mach_timebase_info_data_t gTimebase = {0, 0};

static AudioStreamBasicDescription formatDescription(void) {
    AudioStreamBasicDescription asbd;
    memset(&asbd, 0, sizeof(asbd));
    asbd.mSampleRate = kSampleRate;
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian;
    asbd.mBytesPerPacket = sizeof(Float32) * kChannels;
    asbd.mFramesPerPacket = 1;
    asbd.mBytesPerFrame = sizeof(Float32) * kChannels;
    asbd.mChannelsPerFrame = kChannels;
    asbd.mBitsPerChannel = 32;
    return asbd;
}

static UInt64 hostTicksForFrames(UInt64 frames) {
    if (gTimebase.denom == 0) mach_timebase_info(&gTimebase);
    double nanos = ((double)frames / kSampleRate) * 1000000000.0;
    return (UInt64)(nanos * (double)gTimebase.denom / (double)gTimebase.numer);
}

static bool uuidEquals(REFIID inUUID, CFUUIDRef uuid) {
    CFUUIDBytes bytes = CFUUIDGetUUIDBytes(uuid);
    return memcmp(&inUUID, &bytes, sizeof(CFUUIDBytes)) == 0;
}

static UInt32 streamDirection(AudioObjectID objectID) {
    return objectID == kObjectInputStream ? 1 : 0;
}

static AudioClassID classForObject(AudioObjectID objectID) {
    switch (objectID) {
    case kAudioObjectPlugInObject: return kAudioPlugInClassID;
    case kObjectDevice: return kAudioDeviceClassID;
    case kObjectInputStream:
    case kObjectOutputStream: return kAudioStreamClassID;
    default: return kAudioObjectClassID;
    }
}

static AudioObjectID ownerForObject(AudioObjectID objectID) {
    switch (objectID) {
    case kAudioObjectPlugInObject: return kAudioObjectUnknown;
    case kObjectDevice: return kAudioObjectPlugInObject;
    case kObjectInputStream:
    case kObjectOutputStream: return kObjectDevice;
    default: return kAudioObjectUnknown;
    }
}

static bool validObject(AudioObjectID objectID) {
    return objectID == kAudioObjectPlugInObject || objectID == kObjectDevice ||
           objectID == kObjectInputStream || objectID == kObjectOutputStream;
}

static bool hasProperty(AudioObjectID objectID, const AudioObjectPropertyAddress* address) {
    if (!validObject(objectID)) return false;
    switch (address->mSelector) {
    case kAudioObjectPropertyBaseClass:
    case kAudioObjectPropertyClass:
    case kAudioObjectPropertyOwner:
    case kAudioObjectPropertyName:
    case kAudioObjectPropertyManufacturer:
    case kAudioObjectPropertyOwnedObjects:
        return true;
    case kAudioPlugInPropertyResourceBundle:
        return objectID == kAudioObjectPlugInObject;
    case kAudioDevicePropertyDeviceUID:
    case kAudioDevicePropertyModelUID:
    case kAudioDevicePropertyTransportType:
    case kAudioDevicePropertyDeviceIsAlive:
    case kAudioDevicePropertyDeviceIsRunning:
    case kAudioDevicePropertyDeviceCanBeDefaultDevice:
    case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
    case kAudioDevicePropertyStreams:
    case kAudioDevicePropertyStreamConfiguration:
    case kAudioDevicePropertySafetyOffset:
    case kAudioDevicePropertyLatency:
        return objectID == kObjectDevice || objectID == kObjectInputStream || objectID == kObjectOutputStream;
    case kAudioDevicePropertyNominalSampleRate:
    case kAudioDevicePropertyAvailableNominalSampleRates:
    case kAudioDevicePropertyBufferFrameSize:
    case kAudioDevicePropertyBufferFrameSizeRange:
    case kAudioDevicePropertyUsesVariableBufferFrameSizes:
    case kAudioDevicePropertyIsHidden:
    case kAudioDevicePropertyPreferredChannelsForStereo:
    case kAudioDevicePropertyZeroTimeStampPeriod:
    case kAudioDevicePropertyClockAlgorithm:
    case kAudioDevicePropertyClockIsStable:
        return objectID == kObjectDevice;
    case kAudioStreamPropertyIsActive:
    case kAudioStreamPropertyDirection:
    case kAudioStreamPropertyTerminalType:
    case kAudioStreamPropertyStartingChannel:
    case kAudioStreamPropertyVirtualFormat:
    case kAudioStreamPropertyAvailableVirtualFormats:
    case kAudioStreamPropertyPhysicalFormat:
    case kAudioStreamPropertyAvailablePhysicalFormats:
        return objectID == kObjectInputStream || objectID == kObjectOutputStream;
    default:
        return false;
    }
}

static OSStatus copyOut(UInt32 inDataSize, UInt32* outDataSize, void* outData, const void* source, UInt32 size) {
    if (inDataSize < size) return kAudioHardwareBadPropertySizeError;
    memcpy(outData, source, size);
    *outDataSize = size;
    return noErr;
}

static OSStatus copyCFString(UInt32 inDataSize, UInt32* outDataSize, void* outData, CFStringRef value) {
    CFRetain(value);
    return copyOut(inDataSize, outDataSize, outData, &value, sizeof(CFStringRef));
}

static UInt32 propertySize(AudioObjectID objectID, const AudioObjectPropertyAddress* address) {
    switch (address->mSelector) {
    case kAudioObjectPropertyBaseClass:
    case kAudioObjectPropertyClass:
    case kAudioDevicePropertyTransportType:
    case kAudioDevicePropertyDeviceIsAlive:
    case kAudioDevicePropertyDeviceIsRunning:
    case kAudioDevicePropertyDeviceCanBeDefaultDevice:
    case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
    case kAudioDevicePropertySafetyOffset:
    case kAudioDevicePropertyLatency:
    case kAudioDevicePropertyBufferFrameSize:
    case kAudioDevicePropertyUsesVariableBufferFrameSizes:
    case kAudioDevicePropertyIsHidden:
    case kAudioDevicePropertyZeroTimeStampPeriod:
    case kAudioDevicePropertyClockAlgorithm:
    case kAudioDevicePropertyClockIsStable:
    case kAudioStreamPropertyIsActive:
    case kAudioStreamPropertyDirection:
    case kAudioStreamPropertyTerminalType:
    case kAudioStreamPropertyStartingChannel:
        return sizeof(UInt32);
    case kAudioObjectPropertyOwner:
        return sizeof(AudioObjectID);
    case kAudioObjectPropertyName:
    case kAudioObjectPropertyManufacturer:
    case kAudioPlugInPropertyResourceBundle:
    case kAudioDevicePropertyDeviceUID:
    case kAudioDevicePropertyModelUID:
        return sizeof(CFStringRef);
    case kAudioObjectPropertyOwnedObjects:
        if (objectID == kAudioObjectPlugInObject) return sizeof(AudioObjectID);
        if (objectID == kObjectDevice) return sizeof(AudioObjectID) * 2;
        return 0;
    case kAudioDevicePropertyStreams:
        if (address->mScope == kAudioObjectPropertyScopeInput) return sizeof(AudioObjectID);
        if (address->mScope == kAudioObjectPropertyScopeOutput) return sizeof(AudioObjectID);
        return sizeof(AudioObjectID) * 2;
    case kAudioDevicePropertyStreamConfiguration:
        return offsetof(AudioBufferList, mBuffers) + sizeof(AudioBuffer);
    case kAudioDevicePropertyNominalSampleRate:
        return sizeof(Float64);
    case kAudioDevicePropertyAvailableNominalSampleRates:
    case kAudioDevicePropertyBufferFrameSizeRange:
        return sizeof(AudioValueRange);
    case kAudioDevicePropertyPreferredChannelsForStereo:
        return sizeof(UInt32) * 2;
    case kAudioStreamPropertyVirtualFormat:
    case kAudioStreamPropertyPhysicalFormat:
        return sizeof(AudioStreamBasicDescription);
    case kAudioStreamPropertyAvailableVirtualFormats:
    case kAudioStreamPropertyAvailablePhysicalFormats:
        return sizeof(AudioStreamRangedDescription);
    default:
        return 0;
    }
}

static HRESULT STDMETHODCALLTYPE QueryInterface(void* inDriver, REFIID inUUID, LPVOID* outInterface) {
    if (outInterface == NULL) return E_POINTER;
    if (uuidEquals(inUUID, IUnknownUUID) || uuidEquals(inUUID, kAudioServerPlugInDriverInterfaceUUID)) {
        *outInterface = &gDriverInterfacePtr;
        atomic_fetch_add(&gRefCount, 1);
        return S_OK;
    }
    *outInterface = NULL;
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE AddRef(void* inDriver) {
    return atomic_fetch_add(&gRefCount, 1) + 1;
}

static ULONG STDMETHODCALLTYPE Release(void* inDriver) {
    UInt32 value = atomic_fetch_sub(&gRefCount, 1) - 1;
    return value;
}

static OSStatus STDMETHODCALLTYPE Initialize(AudioServerPlugInDriverRef inDriver, AudioServerPlugInHostRef inHost) {
    gHost = inHost;
    memset(gRing, 0, sizeof(gRing));
    atomic_store(&gWriteFrame, 0);
    atomic_store(&gReadFrame, 0);
    gStartHostTime = mach_absolute_time();
    mach_timebase_info(&gTimebase);
    return noErr;
}

static OSStatus STDMETHODCALLTYPE CreateDevice(AudioServerPlugInDriverRef inDriver, CFDictionaryRef inDescription, const AudioServerPlugInClientInfo* inClientInfo, AudioObjectID* outDeviceObjectID) {
    if (outDeviceObjectID) *outDeviceObjectID = kObjectDevice;
    return noErr;
}

static OSStatus STDMETHODCALLTYPE DestroyDevice(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID) {
    return inDeviceObjectID == kObjectDevice ? noErr : kAudioHardwareBadObjectError;
}

static OSStatus STDMETHODCALLTYPE AddDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo* inClientInfo) {
    return inDeviceObjectID == kObjectDevice ? noErr : kAudioHardwareBadObjectError;
}

static OSStatus STDMETHODCALLTYPE RemoveDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo* inClientInfo) {
    return inDeviceObjectID == kObjectDevice ? noErr : kAudioHardwareBadObjectError;
}

static OSStatus STDMETHODCALLTYPE PerformDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt64 inChangeAction, void* inChangeInfo) {
    return noErr;
}

static OSStatus STDMETHODCALLTYPE AbortDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt64 inChangeAction, void* inChangeInfo) {
    return noErr;
}

static Boolean STDMETHODCALLTYPE HasProperty(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress) {
    return hasProperty(inObjectID, inAddress);
}

static OSStatus STDMETHODCALLTYPE IsPropertySettable(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, Boolean* outIsSettable) {
    if (!outIsSettable) return kAudioHardwareIllegalOperationError;
    *outIsSettable = false;
    return hasProperty(inObjectID, inAddress) ? noErr : kAudioHardwareUnknownPropertyError;
}

static OSStatus STDMETHODCALLTYPE GetPropertyDataSize(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32* outDataSize) {
    if (!hasProperty(inObjectID, inAddress)) return kAudioHardwareUnknownPropertyError;
    *outDataSize = propertySize(inObjectID, inAddress);
    return noErr;
}

static OSStatus STDMETHODCALLTYPE GetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32 inDataSize, UInt32* outDataSize, void* outData) {
    if (!hasProperty(inObjectID, inAddress)) return kAudioHardwareUnknownPropertyError;
    switch (inAddress->mSelector) {
    case kAudioObjectPropertyBaseClass: {
        AudioClassID value = inObjectID == kObjectDevice ? kAudioObjectClassID : (inObjectID == kAudioObjectPlugInObject ? kAudioObjectClassID : kAudioObjectClassID);
        return copyOut(inDataSize, outDataSize, outData, &value, sizeof(value));
    }
    case kAudioObjectPropertyClass: {
        AudioClassID value = classForObject(inObjectID);
        return copyOut(inDataSize, outDataSize, outData, &value, sizeof(value));
    }
    case kAudioObjectPropertyOwner: {
        AudioObjectID value = ownerForObject(inObjectID);
        return copyOut(inDataSize, outDataSize, outData, &value, sizeof(value));
    }
    case kAudioObjectPropertyName:
        return copyCFString(inDataSize, outDataSize, outData, CFSTR("VibeCast Virtual Mic"));
    case kAudioObjectPropertyManufacturer:
        return copyCFString(inDataSize, outDataSize, outData, CFSTR("VibeCast"));
    case kAudioPlugInPropertyResourceBundle:
        return copyCFString(inDataSize, outDataSize, outData, CFSTR(""));
    case kAudioObjectPropertyOwnedObjects: {
        if (inObjectID == kAudioObjectPlugInObject) {
            AudioObjectID value = kObjectDevice;
            return copyOut(inDataSize, outDataSize, outData, &value, sizeof(value));
        }
        AudioObjectID streams[2] = {kObjectInputStream, kObjectOutputStream};
        return copyOut(inDataSize, outDataSize, outData, streams, sizeof(streams));
    }
    case kAudioDevicePropertyDeviceUID:
        return copyCFString(inDataSize, outDataSize, outData, CFSTR(kDeviceUID));
    case kAudioDevicePropertyModelUID:
        return copyCFString(inDataSize, outDataSize, outData, CFSTR(kModelUID));
    case kAudioDevicePropertyTransportType: {
        UInt32 value = kAudioDeviceTransportTypeVirtual;
        return copyOut(inDataSize, outDataSize, outData, &value, sizeof(value));
    }
    case kAudioDevicePropertyDeviceIsAlive:
    case kAudioDevicePropertyDeviceCanBeDefaultDevice:
    case kAudioDevicePropertyClockIsStable:
    case kAudioStreamPropertyIsActive: {
        UInt32 value = 1;
        return copyOut(inDataSize, outDataSize, outData, &value, sizeof(value));
    }
    case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
    case kAudioDevicePropertyUsesVariableBufferFrameSizes:
    case kAudioDevicePropertyIsHidden: {
        UInt32 value = 0;
        return copyOut(inDataSize, outDataSize, outData, &value, sizeof(value));
    }
    case kAudioDevicePropertyDeviceIsRunning: {
        UInt32 value = atomic_load(&gRunningClients) > 0 ? 1 : 0;
        return copyOut(inDataSize, outDataSize, outData, &value, sizeof(value));
    }
    case kAudioDevicePropertyStreams: {
        if (inAddress->mScope == kAudioObjectPropertyScopeInput) {
            AudioObjectID value = kObjectInputStream;
            return copyOut(inDataSize, outDataSize, outData, &value, sizeof(value));
        }
        if (inAddress->mScope == kAudioObjectPropertyScopeOutput) {
            AudioObjectID value = kObjectOutputStream;
            return copyOut(inDataSize, outDataSize, outData, &value, sizeof(value));
        }
        AudioObjectID streams[2] = {kObjectInputStream, kObjectOutputStream};
        return copyOut(inDataSize, outDataSize, outData, streams, sizeof(streams));
    }
    case kAudioDevicePropertyStreamConfiguration: {
        if (inDataSize < propertySize(inObjectID, inAddress)) return kAudioHardwareBadPropertySizeError;
        AudioBufferList* list = (AudioBufferList*)outData;
        list->mNumberBuffers = 1;
        list->mBuffers[0].mNumberChannels = kChannels;
        list->mBuffers[0].mDataByteSize = 0;
        list->mBuffers[0].mData = NULL;
        *outDataSize = propertySize(inObjectID, inAddress);
        return noErr;
    }
    case kAudioDevicePropertySafetyOffset:
    case kAudioDevicePropertyLatency: {
        UInt32 value = 0;
        return copyOut(inDataSize, outDataSize, outData, &value, sizeof(value));
    }
    case kAudioDevicePropertyNominalSampleRate: {
        Float64 value = kSampleRate;
        return copyOut(inDataSize, outDataSize, outData, &value, sizeof(value));
    }
    case kAudioDevicePropertyAvailableNominalSampleRates:
    case kAudioDevicePropertyBufferFrameSizeRange: {
        AudioValueRange value = { kSampleRate, kSampleRate };
        if (inAddress->mSelector == kAudioDevicePropertyBufferFrameSizeRange) {
            value.mMinimum = 64;
            value.mMaximum = 4096;
        }
        return copyOut(inDataSize, outDataSize, outData, &value, sizeof(value));
    }
    case kAudioDevicePropertyBufferFrameSize: {
        UInt32 value = 512;
        return copyOut(inDataSize, outDataSize, outData, &value, sizeof(value));
    }
    case kAudioDevicePropertyPreferredChannelsForStereo: {
        UInt32 value[2] = {1, 2};
        return copyOut(inDataSize, outDataSize, outData, value, sizeof(value));
    }
    case kAudioDevicePropertyZeroTimeStampPeriod: {
        UInt32 value = kZeroTimeStampPeriod;
        return copyOut(inDataSize, outDataSize, outData, &value, sizeof(value));
    }
    case kAudioDevicePropertyClockAlgorithm: {
        UInt32 value = kAudioDeviceClockAlgorithmRaw;
        return copyOut(inDataSize, outDataSize, outData, &value, sizeof(value));
    }
    case kAudioStreamPropertyDirection: {
        UInt32 value = streamDirection(inObjectID);
        return copyOut(inDataSize, outDataSize, outData, &value, sizeof(value));
    }
    case kAudioStreamPropertyTerminalType: {
        UInt32 value = streamDirection(inObjectID) ? kAudioStreamTerminalTypeMicrophone : kAudioStreamTerminalTypeSpeaker;
        return copyOut(inDataSize, outDataSize, outData, &value, sizeof(value));
    }
    case kAudioStreamPropertyStartingChannel: {
        UInt32 value = 1;
        return copyOut(inDataSize, outDataSize, outData, &value, sizeof(value));
    }
    case kAudioStreamPropertyVirtualFormat:
    case kAudioStreamPropertyPhysicalFormat: {
        AudioStreamBasicDescription value = formatDescription();
        return copyOut(inDataSize, outDataSize, outData, &value, sizeof(value));
    }
    case kAudioStreamPropertyAvailableVirtualFormats:
    case kAudioStreamPropertyAvailablePhysicalFormats: {
        AudioStreamRangedDescription value;
        value.mFormat = formatDescription();
        value.mSampleRateRange.mMinimum = kSampleRate;
        value.mSampleRateRange.mMaximum = kSampleRate;
        return copyOut(inDataSize, outDataSize, outData, &value, sizeof(value));
    }
    default:
        return kAudioHardwareUnknownPropertyError;
    }
}

static OSStatus STDMETHODCALLTYPE SetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32 inDataSize, const void* inData) {
    return kAudioHardwareIllegalOperationError;
}

static OSStatus STDMETHODCALLTYPE StartIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID) {
    if (inDeviceObjectID != kObjectDevice) return kAudioHardwareBadObjectError;
    atomic_fetch_add(&gRunningClients, 1);
    return noErr;
}

static OSStatus STDMETHODCALLTYPE StopIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID) {
    if (inDeviceObjectID != kObjectDevice) return kAudioHardwareBadObjectError;
    UInt32 current = atomic_load(&gRunningClients);
    if (current > 0) atomic_fetch_sub(&gRunningClients, 1);
    return noErr;
}

static OSStatus STDMETHODCALLTYPE GetZeroTimeStamp(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, Float64* outSampleTime, UInt64* outHostTime, UInt64* outSeed) {
    if (inDeviceObjectID != kObjectDevice) return kAudioHardwareBadObjectError;
    UInt64 now = mach_absolute_time();
    UInt64 elapsed = now - gStartHostTime;
    double nanos = (double)elapsed * (double)gTimebase.numer / (double)gTimebase.denom;
    Float64 sampleTime = (nanos / 1000000000.0) * kSampleRate;
    UInt64 period = kZeroTimeStampPeriod;
    UInt64 periodIndex = (UInt64)(sampleTime / (Float64)period);
    *outSampleTime = (Float64)(periodIndex * period);
    *outHostTime = gStartHostTime + hostTicksForFrames(periodIndex * period);
    *outSeed = 1;
    return noErr;
}

static OSStatus STDMETHODCALLTYPE WillDoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, Boolean* outWillDo, Boolean* outWillDoInPlace) {
    *outWillDo = (inOperationID == kAudioServerPlugInIOOperationReadInput || inOperationID == kAudioServerPlugInIOOperationWriteMix);
    *outWillDoInPlace = true;
    return noErr;
}

static OSStatus STDMETHODCALLTYPE BeginIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo) {
    return noErr;
}

static OSStatus STDMETHODCALLTYPE DoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, AudioObjectID inStreamObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo, void* ioMainBuffer, void* ioSecondaryBuffer) {
    if (ioMainBuffer == NULL) return noErr;
    Float32* buffer = (Float32*)ioMainBuffer;
    if (inOperationID == kAudioServerPlugInIOOperationWriteMix && inStreamObjectID == kObjectOutputStream) {
        UInt64 write = atomic_load_explicit(&gWriteFrame, memory_order_relaxed);
        for (UInt32 frame = 0; frame < inIOBufferFrameSize; frame++) {
            UInt64 index = ((write + frame) % kRingFrames) * kChannels;
            gRing[index] = buffer[frame * kChannels];
            gRing[index + 1] = buffer[frame * kChannels + 1];
        }
        atomic_store_explicit(&gWriteFrame, write + inIOBufferFrameSize, memory_order_release);
        return noErr;
    }
    if (inOperationID == kAudioServerPlugInIOOperationReadInput && inStreamObjectID == kObjectInputStream) {
        UInt64 write = atomic_load_explicit(&gWriteFrame, memory_order_acquire);
        UInt64 read = atomic_load_explicit(&gReadFrame, memory_order_relaxed);
        if (write > read + kRingFrames) {
            read = write - inIOBufferFrameSize;
        }
        UInt64 available = write > read ? write - read : 0;
        UInt32 silenceFrames = available < inIOBufferFrameSize ? (UInt32)(inIOBufferFrameSize - available) : 0;
        for (UInt32 frame = 0; frame < silenceFrames; frame++) {
            buffer[frame * kChannels] = 0.0f;
            buffer[frame * kChannels + 1] = 0.0f;
        }
        UInt32 copyFrames = inIOBufferFrameSize - silenceFrames;
        for (UInt32 frame = 0; frame < copyFrames; frame++) {
            UInt64 index = ((read + frame) % kRingFrames) * kChannels;
            UInt32 dest = silenceFrames + frame;
            buffer[dest * kChannels] = gRing[index];
            buffer[dest * kChannels + 1] = gRing[index + 1];
        }
        atomic_store_explicit(&gReadFrame, read + copyFrames, memory_order_release);
    }
    return noErr;
}

static OSStatus STDMETHODCALLTYPE EndIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo) {
    return noErr;
}

static AudioServerPlugInDriverInterface gDriverInterface = {
    NULL,
    QueryInterface,
    AddRef,
    Release,
    Initialize,
    CreateDevice,
    DestroyDevice,
    AddDeviceClient,
    RemoveDeviceClient,
    PerformDeviceConfigurationChange,
    AbortDeviceConfigurationChange,
    HasProperty,
    IsPropertySettable,
    GetPropertyDataSize,
    GetPropertyData,
    SetPropertyData,
    StartIO,
    StopIO,
    GetZeroTimeStamp,
    WillDoIOOperation,
    BeginIOOperation,
    DoIOOperation,
    EndIOOperation
};

void* VibeCastVirtualMicFactory(CFAllocatorRef allocator, CFUUIDRef typeUUID) {
    if (CFEqual(typeUUID, kAudioServerPlugInTypeUUID)) {
        return &gDriverInterfacePtr;
    }
    return NULL;
}
