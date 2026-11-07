#ifndef CPRIVATE_H
#define CPRIVATE_H

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>

// Private but long-stable system functions, declared the way LinearMouse declares them.

/// A full event system client. Unlike the public simple client, it may change service
/// properties such as a mouse's pointer resolution and acceleration.
extern IOHIDEventSystemClientRef _Nullable IOHIDEventSystemClientCreate(CFAllocatorRef _Nullable allocator) CF_RETURNS_RETAINED;

/// Asks the Dock to show Mission Control, App Exposé or the desktop.
extern CGError CoreDockSendNotification(CFStringRef _Nonnull notification, int unknown);

typedef CFTypeRef IOHIDEventRef;
typedef uint32_t IOHIDEventField;
#define MM_IOHIDEventTypeScroll 6
static const IOHIDEventField MMIOHIDEventFieldScrollX = (MM_IOHIDEventTypeScroll << 16) | 0;
static const IOHIDEventField MMIOHIDEventFieldScrollY = (MM_IOHIDEventTypeScroll << 16) | 1;

/// The HID event a Quartz event came from, or NULL for synthetic events.
extern IOHIDEventRef _Nullable CGEventCopyIOHIDEvent(CGEventRef _Nonnull event) CF_RETURNS_RETAINED;
/// The registry ID of the HID service that sent the event.
extern uint64_t IOHIDEventGetSenderID(IOHIDEventRef _Nonnull event);
extern double IOHIDEventGetFloatValue(IOHIDEventRef _Nonnull event, IOHIDEventField field);
extern void IOHIDEventSetFloatValue(IOHIDEventRef _Nonnull event, IOHIDEventField field, double value);

#endif
