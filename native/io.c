/* OS/Unicode boundary only: no table parsing or conversion. */
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <utf8proc.h>
#ifdef _WIN32
#include <windows.h>
#include <io.h>
#include <process.h>
#include <fcntl.h>
#define fileno _fileno
#define dup _dup
#define dup2 _dup2
#define close _close
#else
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <spawn.h>
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif
extern char **environ;
#endif
#ifndef TABLE_RENDERER
#define TABLE_RENDERER "tsv-to-ansi-table"
#endif
#ifndef TABLE_ABOUT
#define TABLE_ABOUT "table 0.1.0"
#endif
typedef struct { unsigned char *data; size_t len; } TableBytes;
typedef struct { TableBytes out, err; int status; } TableProcess;
void table_free(void *p) { free(p); }
const char *table_about(void) { return TABLE_ABOUT; }
static int read_file(FILE *f, TableBytes *b) {
    size_t cap=4096; b->len=0; b->data=malloc(cap); if(!b->data) return -1;
    for(;;) {
        if(b->len==cap) { if(cap>SIZE_MAX/2) goto fail; cap*=2; void *p=realloc(b->data,cap); if(!p) goto fail; b->data=p; }
        size_t n=fread(b->data+b->len,1,cap-b->len,f); b->len+=n;
        if(!n) { if(ferror(f)) goto fail; return 0; }
    }
fail: free(b->data); b->data=NULL; return -1;
}
int table_read(TableBytes *b) {
#ifdef _WIN32
    _setmode(_fileno(stdin),_O_BINARY); _setmode(_fileno(stdout),_O_BINARY);
#endif
    return read_file(stdin,b);
}
int table_write(int stream,const unsigned char *s,size_t n) {
    FILE *f=stream==2?stderr:stdout;
#ifdef _WIN32
    _setmode(_fileno(f),_O_BINARY);
#endif
    return fwrite(s,1,n,f)==n && fflush(f)==0 ? 0:-1;
}
uint64_t table_columns(void) {
#ifdef _WIN32
    CONSOLE_SCREEN_BUFFER_INFO info; HANDLE h=GetStdHandle(STD_OUTPUT_HANDLE); DWORD mode;
    return GetConsoleMode(h,&mode)&&GetConsoleScreenBufferInfo(h,&info)?(uint64_t)(info.srWindow.Right-info.srWindow.Left+1):0;
#else
    struct winsize size; return isatty(1)&&ioctl(1,TIOCGWINSZ,&size)==0?size.ws_col:0;
#endif
}
int table_tty(void) {
#ifdef _WIN32
    DWORD mode; return GetConsoleMode(GetStdHandle(STD_OUTPUT_HANDLE),&mode)!=0;
#else
    return isatty(1);
#endif
}
int table_next(const unsigned char *s,size_t n,int32_t *cp) { return (int)utf8proc_iterate(s,(utf8proc_ssize_t)n,cp); }
int table_category(int32_t cp) { return utf8proc_category(cp); }
int table_white(int32_t c) { return (c>=9&&c<=13)||c==32||c==0x85||c==0xa0||c==0x1680||(c>=0x2000&&c<=0x200a)||c==0x2028||c==0x2029||c==0x202f||c==0x205f||c==0x3000; }
uint64_t table_env_columns(void) {
    const char *s=getenv("COLUMNS"); if(!s) return 0;
    size_t n=strlen(s),i=0;
    while(i<n) { int32_t cp; int k=table_next((const unsigned char *)s+i,n-i,&cp); if(k<=0) return 0; if(!table_white(cp)) break; i+=(size_t)k; }
    if(i<n&&s[i]=='+') i++;
    if(i==n) return 0;
    uint64_t value=0;
    for(;i<n;i++) { if(s[i]<'0'||s[i]>'9') return 0; value=value*10+(unsigned)(s[i]-'0'); if(value>10000) return 0; }
    return value;
}
int table_safe(int32_t cp) { int c=table_category(cp); return !(c>=24&&c<=26) && !(c==27&&cp!=0x200c&&cp!=0x200d&&!(cp>=0xe0020&&cp<=0xe007f)); }
int64_t table_width(const unsigned char *s,size_t n) {
    size_t i=0; int32_t previous=0,state=0; int64_t total=0,cells=0;
    while(i<n) { int32_t cp; int k=table_next(s+i,n-i,&cp); if(k<=0) return -1;
        if(i&&utf8proc_grapheme_break_stateful(previous,cp,&state)) { total+=cells; cells=0; }
        int category=table_category(cp); int w=(category==6||category==8||category==27)?0:utf8proc_charwidth(cp);
        if(w<0) w=0; if(cp==0xfe0f||cp==0x20e3||(cp>=0x1f1e6&&cp<=0x1f1ff)) w=2;
        if(w>cells) cells=w; previous=cp; i+=(size_t)k;
    } return total+cells;
}
const char *table_renderer(void) {
    static char path[32768]; size_t n=0;
#ifdef _WIN32
    n=GetModuleFileNameA(NULL,path,sizeof(path));
#elif defined(__APPLE__)
    uint32_t size=sizeof(path); if(_NSGetExecutablePath(path,&size)!=0) return TABLE_RENDERER; n=strlen(path);
#else
    ssize_t k=readlink("/proc/self/exe",path,sizeof(path)-1); if(k<0) return TABLE_RENDERER; n=(size_t)k; path[n]=0;
#endif
    if(!n||n>=sizeof(path)-128) return TABLE_RENDERER;
    char *slash=strrchr(path,'/');
#ifdef _WIN32
    char *back=strrchr(path,'\\'); if(back&&(!slash||back>slash)) slash=back;
    const char *name="tsv-to-ansi-table.exe";
#else
    const char *name="tsv-to-ansi-table";
#endif
    if(!slash) return TABLE_RENDERER;
    size_t base=(size_t)(slash-path); snprintf(path+base,sizeof(path)-base,"/libexec/%s",name);
    FILE *f=fopen(path,"rb"); if(f) { fclose(f); return path; }
    path[base]=0; slash=strrchr(path,'/');
    if(slash) { snprintf(slash,sizeof(path)-(size_t)(slash-path),"/libexec/%s",name); f=fopen(path,"rb"); if(f) { fclose(f); return path; } }
    return TABLE_RENDERER;
}
/* argv is NUL-terminated; arbitrary input/output always uses pointer+length.
 * Outputs are owned by caller and released with table_free. */
int table_process(const char *program,char *const *argv,const unsigned char *input,size_t length,int inherit,TableProcess *r) {
    memset(r,0,sizeof(*r)); FILE *in=NULL,*out=NULL,*err=NULL;
    if(!inherit) { in=tmpfile(); out=tmpfile(); err=tmpfile(); if(!in||!out||!err) goto fail;
        if(fwrite(input,1,length,in)!=length||fflush(in)) goto fail; rewind(in); }
#ifdef _WIN32
    int saved[3]={-1,-1,-1};
    if(!inherit) { for(int i=0;i<3;i++) saved[i]=dup(i); if(dup2(fileno(in),0)||dup2(fileno(out),1)||dup2(fileno(err),2)) goto fail; }
    intptr_t status=_spawnv(_P_WAIT,program,(const char *const *)argv);
    if(!inherit) for(int i=0;i<3;i++) { dup2(saved[i],i); close(saved[i]); }
    if(status<0) goto fail; r->status=(int)status;
#else
    posix_spawn_file_actions_t actions; if(posix_spawn_file_actions_init(&actions)) goto fail;
    if(!inherit) { posix_spawn_file_actions_adddup2(&actions,fileno(in),0); posix_spawn_file_actions_adddup2(&actions,fileno(out),1); posix_spawn_file_actions_adddup2(&actions,fileno(err),2); }
    pid_t pid; int rc=posix_spawn(&pid,program,&actions,NULL,argv,environ); posix_spawn_file_actions_destroy(&actions); if(rc) goto fail;
    int status; while(waitpid(pid,&status,0)<0) { if(errno!=EINTR) goto fail; }
    r->status=WIFEXITED(status)?WEXITSTATUS(status):128+WTERMSIG(status);
#endif
    if(!inherit) { rewind(out); rewind(err); if(read_file(out,&r->out)||read_file(err,&r->err)) goto fail; fclose(in); fclose(out); fclose(err); }
    return 0;
fail:
    if(in) fclose(in); if(out) fclose(out); if(err) fclose(err);
    free(r->out.data); free(r->err.data); memset(r,0,sizeof(*r)); return -1;
}
