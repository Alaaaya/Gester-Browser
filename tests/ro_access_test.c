#define _GNU_SOURCE
#include "../src/ROAccess.h"
#include <assert.h>
#include <stdio.h>
#include <sys/stat.h>
int main(void) {
    char base[] = "/tmp/ro-browser-XXXXXX";
    assert(mkdtemp(base));
    int root = open(base, O_RDONLY | O_DIRECTORY);
    assert(root >= 0);
    // Fixtures only; browser module contains no filesystem mutation calls.
    assert(mkdirat(root, "child", 0700) == 0);
    int fixture = openat(root, "child/test.txt", O_CREAT | O_WRONLY, 0600);
    assert(fixture >= 0); assert(write(fixture, "read only", 9) == 9); close(fixture);
    assert(symlinkat("/etc", root, "external") == 0);
    assert(symlinkat("child/test.txt", root, "link") == 0);
    const char *rejected[] = {"../etc/passwd", "/etc/passwd", "child/../child/test.txt",
        "child//test.txt", "./child", "child/", "external/passwd", "link", "missing"};
    for (unsigned i = 0; i < sizeof(rejected)/sizeof(*rejected); i++) assert(ROOpenRelative(root, rejected[i]) < 0);
    int file = ROOpenRelative(root, "child/test.txt");
    assert(file >= 0);
    assert((fcntl(file, F_GETFL) & O_ACCMODE) == O_RDONLY);
    char buf[10] = {0}; assert(read(file, buf, 9) == 9); assert(!strcmp(buf, "read only")); close(file);
    int same = ROOpenRelative(root, ""); assert(same >= 0); close(same);
    assert(ROOpenRelative(-1, "") < 0);
    unlinkat(root, "link", 0); unlinkat(root, "external", 0);
    unlinkat(root, "child/test.txt", 0); unlinkat(root, "child", AT_REMOVEDIR);
    close(root); rmdir(base);
    puts("PASS read-only open, child reads, root duplication, invalid root, nine path/link rejection cases");
}
