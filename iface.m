/*
    Pynetinfo - A python module for controlling linux network interfaces
    Copyright (C) 2010  Sassan Panahinejad (sassan@sassan.me.uk)
    www.sassan.me.uk
    pypi.python.org/pypi/pynetinfo/

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
*/
#include <Python.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <net/if.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <net/route.h>
#include <Foundation/Foundation.h>
#include <SystemConfiguration/SystemConfiguration.h>

#include "netinfo.h"

#define IF_COUNT 64

char *getKeyFromInterfaceStore(char *interface, NSString *key) {
    SCDynamicStoreRef storeRef = SCDynamicStoreCreate(NULL, (CFStringRef)@"pynetinfo", NULL, NULL);
    
    NSString *interfaceState = [[@"State:/Network/Interface/" stringByAppendingString:[NSString stringWithUTF8String:interface]] stringByAppendingString:@"/IPv4"];
    CFPropertyListRef ipv4 = SCDynamicStoreCopyValue(storeRef, (CFStringRef)interfaceState);
    char *data = [[[(NSDictionary *)ipv4 valueForKey:key] objectAtIndex:0] UTF8String];
    
    CFRelease(storeRef);
    return data;
}

PyObject *netinfo_list_active_devs(PyObject *self, PyObject *args)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    PyObject *tuple = PyTuple_New(0);
    NSArray *networkArray = SCNetworkInterfaceCopyAll();
    int i, j=0;
    for (i=0;i<[networkArray count];i++) {
        SCNetworkInterfaceRef interface = [networkArray objectAtIndex:i];
        if (getKeyFromInterfaceStore([(NSString *)SCNetworkInterfaceGetBSDName(interface) UTF8String], @"Addresses")) {
            _PyTuple_Resize(&tuple, j+1);
            PyTuple_SET_ITEM(tuple, j, Py_BuildValue("s", [(NSString *)SCNetworkInterfaceGetBSDName(interface) UTF8String]));
            j++;
        }
    }
    CFRelease(networkArray);
    [pool drain];
    return tuple;
}

PyObject *netinfo_list_devs(PyObject *self, PyObject *args)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    PyObject *tuple = PyTuple_New(0);
    CFArrayRef networkArray = SCNetworkInterfaceCopyAll();
    int i;
    for (i=0;i<CFArrayGetCount(networkArray);i++) {
        SCNetworkInterfaceRef interface = CFArrayGetValueAtIndex(networkArray, i);
        _PyTuple_Resize(&tuple, i+1);
        PyTuple_SET_ITEM(tuple, i, Py_BuildValue("s", [(NSString *)SCNetworkInterfaceGetBSDName(interface) UTF8String]));
    }
    CFRelease(networkArray);
    [pool drain];
    return tuple;
}

PyObject *netinfo_get_addr(PyObject *self, PyObject *args, NSString *cmd)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int ret;
    char *dev;
    ret = PyArg_ParseTuple(args, "s", &dev); /* parse argument */
    if (!ret) return NULL;
    CFArrayRef networkArray = SCNetworkInterfaceCopyAll();
    int i;
    for (i=0;i<CFArrayGetCount(networkArray);i++) {
        SCNetworkInterfaceRef interface = CFArrayGetValueAtIndex(networkArray, i);
        int length;
        CFStringRef name = SCNetworkInterfaceGetBSDName(interface);
        if ([name isEqualToString:[NSString stringWithUTF8String:dev]]) {
            if (!cmd) {
                NSString *MAC = (NSString *)SCNetworkInterfaceGetHardwareAddressString(interface);
                return Py_BuildValue("s", (MAC)?[MAC UTF8String]:"");
            } else {
                char *address = getKeyFromInterfaceStore(dev, @"Addresses");
                CFRelease(networkArray);
                [pool drain];
                return Py_BuildValue("s", (address)?address:"");
            }
        }
    }
    CFRelease(networkArray);
    [pool drain];
    return Py_BuildValue("s", "");
}

PyObject *netinfo_get_ip(PyObject *self, PyObject *args)
{
    return netinfo_get_addr(self, args, @"Addresses");
}

PyObject *netinfo_get_netmask(PyObject *self, PyObject *args)
{
    return netinfo_get_addr(self, args, @"SubnetMasks");
}

PyObject *netinfo_get_broadcast(PyObject *self, PyObject *args)
{
    return netinfo_get_addr(self, args, @"BroadcastAddresses");
}

PyObject *netinfo_get_hwaddr(PyObject *self, PyObject *args)
{
    return netinfo_get_addr(self, args, nil);
}

PyObject *netinfo_set_state(PyObject *self, PyObject *args)
{
    int ret, fd, state = 0;
    struct ifreq ifreq;
    char *dev;
    ret = PyArg_ParseTuple(args, "si", &dev, &state); /* parse argument */
    if (!ret)
        return NULL;
//     ret = PyArg_ParseTuple(args, "i", &state); /* parse argument */
//     if (!ret)
//         return NULL;
    fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_IP); /* open a socket to examine */
    if (fd < 0) {
        PyErr_SetFromErrno(PyExc_Exception);
        return NULL;
    }
    memset(&ifreq, 0, sizeof(struct ifreq));
    strncpy(ifreq.ifr_name, dev, IFNAMSIZ-1);
    ret = ioctl(fd, SIOCGIFFLAGS, &ifreq);
    if (ret < 0) {
        PyErr_SetFromErrno(PyExc_Exception);
        return NULL;
    }
    if (state)
        ifreq.ifr_flags |= IFF_UP;
    else
        ifreq.ifr_flags &= ~IFF_UP;
    ret = ioctl(fd, SIOCSIFFLAGS, &ifreq);
    if (ret < 0) {
        PyErr_SetFromErrno(PyExc_Exception);
        return NULL;
    }
    return Py_None;
}

PyObject *netinfo_set_addr(PyObject *self, PyObject *args, int cmd)
{
    // Untested on Mac, but probably works
    int ret;
    char *dev, *addr;
    ret = PyArg_ParseTuple(args, "ss", &dev, &addr); // parse argument
    if (!ret) return NULL;
    SCDynamicStoreRef storeRef = SCDynamicStoreCreate(NULL, CFSTR("netinfo_set_addr"), NULL, NULL);
    NSString *interfaceState = @"State:/Network/Interface/";
    interfaceState = [[interfaceState stringByAppendingString:[NSString stringWithUTF8String:dev]] stringByAppendingString:@"/IPv4"];
    switch (cmd) {
        case SIOCSIFADDR:
            interfaceState = [interfaceState stringByAppendingString:@"Addresses"];
            SCDynamicStoreSetValue(storeRef, interfaceState, [NSArray arrayWithObject:[NSString stringWithUTF8String:addr]]);
            break;
        case SIOCSIFNETMASK:
            interfaceState = [interfaceState stringByAppendingString:@"SubnetMasks"];
            SCDynamicStoreSetValue(storeRef, interfaceState, [NSArray arrayWithObject:[NSString stringWithUTF8String:addr]]);
            break;
        case SIOCSIFBRDADDR:
            interfaceState = [interfaceState stringByAppendingString:@"BroadcastAddresses"];
            SCDynamicStoreSetValue(storeRef, interfaceState, [NSArray arrayWithObject:[NSString stringWithUTF8String:addr]]);
            break;
    }
    CFRelease(storeRef);
    return Py_None;
}

PyObject *netinfo_set_ip(PyObject *self, PyObject *args)
{
    return netinfo_set_addr(self, args, SIOCSIFADDR);
}

PyObject *netinfo_set_netmask(PyObject *self, PyObject *args)
{
    return netinfo_set_addr(self, args, SIOCSIFNETMASK);
}

PyObject *netinfo_set_broadcast(PyObject *self, PyObject *args)
{
    return netinfo_set_addr(self, args, SIOCSIFBRDADDR);
}




