#define _GNU_SOURCE
#include "../src/GBSafeWrite.h"
#include <assert.h>
int main(void) {
    const char *bad[] = {"", ".", "..", "/absolute", "../outside", "a/b", "a\\b"};
    for (unsigned i=0;i<sizeof(bad)/sizeof(*bad);i++) assert(!GBValidName(bad[i]));
    char base[]="/tmp/gb-write-XXXXXX"; assert(mkdtemp(base));
    int parent=open(base,O_RDONLY|O_DIRECTORY); assert(parent>=0);
    assert(GBCreateFile(parent,"original.txt","original",8)==0);
    assert(GBCreateFile(parent,"original.txt","bad",3)<0);
    assert(symlinkat("original.txt",parent,"link")==0);
    assert(GBCreateFile(parent,"link","bad",3)<0);
    assert(GBCreateFile(parent,"../outside","bad",3)<0);
    assert(GBMakeFolder(parent,"folder")==0);
    assert(GBMakeFolder(parent,"folder")<0);
    assert(GBMakeFolder(parent,"link")<0);
    assert(GBCreateFile(parent,"copy.txt","original",8)==0);
    assert(GBCreateFile(parent,"empty",NULL,0)==0);
    int fd=ROOpenRelative(parent,"original.txt"); char bytes[9]={0};
    assert(read(fd,bytes,8)==8 && !strcmp(bytes,"original")); close(fd);
#ifdef __APPLE__
    assert(GBRenameExclusive(parent,"copy.txt","original.txt")<0);
    assert(GBRenameExclusive(parent,"copy.txt","renamed.txt")==0);
    assert(ROOpenRelative(parent,"copy.txt")<0);
    unlinkat(parent,"renamed.txt",0);
#else
    assert(GBRenameExclusive(parent,"copy.txt","renamed.txt")<0);
    unlinkat(parent,"copy.txt",0);
#endif
    unlinkat(parent,"original.txt",0); unlinkat(parent,"link",0);
    unlinkat(parent,"empty",0); unlinkat(parent,"folder",AT_REMOVEDIR);
    close(parent); rmdir(base);
    puts("PASS create-only files/folders, symlink/name/conflict rejection, original preservation, exclusive rename policy");
}
