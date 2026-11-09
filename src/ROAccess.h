// Read-only descriptor-relative access policy. No link traversal or parent paths.
#ifndef RO_ACCESS_H
#define RO_ACCESS_H
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
static inline int ROOpenRelative(int root, const char *relative) {
    if (!relative || relative[0] == '/') { errno = EINVAL; return -1; }
    int fd = dup(root);
    if (fd < 0 || !relative[0]) return fd;
    char *copy = strdup(relative);
    if (!copy) { close(fd); return -1; }
    char *part = copy;
    while (part) {
        char *next = strchr(part, '/');
        if (next) *next++ = 0;
        if (!*part || !strcmp(part, ".") || !strcmp(part, "..")) {
            close(fd); free(copy); errno = EINVAL; return -1;
        }
        int flags = O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC;
        if (next) flags |= O_DIRECTORY;
        int child = openat(fd, part, flags);
        close(fd); fd = child;
        if (fd < 0) break;
        part = next;
    }
    free(copy);
    return fd;
}
#endif
