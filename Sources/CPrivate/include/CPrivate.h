#ifndef CPRIVATE_H
#define CPRIVATE_H

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>

// Private but long-stable system functions, also used by LinearMouse and similar utilities.

/// A full event system client. Unlike the public simple client, it may change service
/// properties such as a mouse's pointer resolution and acceleration.
extern IOHIDEventSystemClientRef _Nullable IOHIDEventSystemClientCreate(CFAllocatorRef _Nullable allocator) CF_RETURNS_RETAINED;

/// Asks the Dock to show Mission Control, App Exposé, the desktop or Launchpad.
extern CGError CoreDockSendNotification(CFStringRef _Nonnull notification, int unknown);

#endif
