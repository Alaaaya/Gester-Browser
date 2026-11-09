// Ordinary document operations only. No BQCore, sandbox extensions or escape state.
#ifndef GB_SAFE_WRITE_H
#define GB_SAFE_WRITE_H
#include "ROAccess.h"
#include <sys/stat.h>
#include <stdio.h>
static inline int GBValidName(const char *name) {
    return name && *name && strlen(name) <= 240 && strcmp(name, ".") &&
        strcmp(name, "..") && !strchr(name, '/') && !strchr(name, '\\');
}
// Create-only publication. Never replace a destination, including a symlink.
// Never unlink on failure: a concurrent writer may have replaced the name.
// An incomplete NEW copy may remain. Original files are never overwritten.
static inline int GBCreateFile(int parent, const char *name, const void *bytes, size_t length) {
    if (!GBValidName(name)) { errno = EINVAL; return -1; }
    int fd = openat(parent, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0) return -1;
    size_t offset = 0;
    while (offset < length) {
        ssize_t n = write(fd, (const char *)bytes + offset, length - offset);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) { int e = errno; close(fd); errno = e; return -1; }
        offset += (size_t)n;
    }
    if (fsync(fd)) { int e=errno; close(fd); errno=e; return -1; }
    return close(fd);
}
static inline int GBMakeFolder(int parent, const char *name) {
    if (!GBValidName(name)) { errno=EINVAL; return -1; }
    return mkdirat(parent,name,0700);
}
static inline int GBRenameExclusive(int parent, const char *source, const char *destination) {
    if (!GBValidName(source) || !GBValidName(destination)) { errno=EINVAL; return -1; }
#ifdef __APPLE__
    return renameatx_np(parent,source,parent,destination,RENAME_EXCL);
#else
    (void)parent;
    // No unsafe check-then-overwriting-rename fallback on other platforms.
    errno=ENOTSUP; return -1;
#endif
}
#endif
