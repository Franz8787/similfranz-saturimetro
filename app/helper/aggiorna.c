// similfranz-sat-aggiorna — aiutante di installazione del saturimetro (setuid root, installato dal pacchetto).
// L'app (utente mobile) non può usare dpkg: lascia il .deb in un percorso FISSO e avvia questo programma, che
//   1. diventa root, ripulisce l'ambiente;
//   2. accetta il file solo se dpkg-deb dice che è il pacchetto del saturimetro;
//   3. si stacca dall'app (che verrà chiusa), installa con dpkg, cancella il file e riapre l'app.
// Non accetta argomenti né percorsi: nient'altro può essere installato tramite lui.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <signal.h>

#define DEB  "/var/mobile/Library/Caches/similfranz-aggiornamento.deb"
#define LOG  "/var/mobile/Library/Caches/similfranz-aggiornamento.log"
#define PKG  "it.simulafranz.saturimetro"

int main(void) {
    if (setgid(0) != 0 || setuid(0) != 0) { fprintf(stderr, "non posso diventare root\n"); return 1; }
    static char *vuoto[] = { NULL }; extern char **environ; environ = vuoto;     // ambiente ripulito
    setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin", 1);
    struct stat st;
    if (lstat(DEB, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size > 4 * 1024 * 1024) { fprintf(stderr, "pacchetto assente\n"); return 2; }
    FILE *p = popen("/usr/bin/dpkg-deb -f '" DEB "' Package", "r");
    char name[128] = {0};
    if (!p || !fgets(name, sizeof name, p)) { if (p) pclose(p); return 3; }
    pclose(p);
    name[strcspn(name, "\r\n")] = 0;
    if (strcmp(name, PKG) != 0) { fprintf(stderr, "pacchetto non valido: %s\n", name); unlink(DEB); return 4; }

    pid_t app = getppid();                // l'app che ci ha chiamato: va chiusa e riaperta dopo l'installazione
    pid_t pid = fork();
    if (pid < 0) return 5;
    if (pid > 0) return 0;                // l'app riceve subito la risposta
    setsid();
    int fd = open(LOG, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) { dup2(fd, 1); dup2(fd, 2); close(fd); }
    sleep(2);                             // tempo per la risposta HTTP alla console
    int rc = system("/usr/bin/dpkg -i '" DEB "'");
    printf("dpkg: %d\n", rc); fflush(stdout);
    unlink(DEB);
    if (app > 1) kill(app, SIGKILL);      // per numero di processo: su iOS i nomi lunghi sono accorciati
    system("/usr/bin/killall SimulaFranz_Saturimetro 2>/dev/null");
    sleep(2);
    system("/bin/su mobile -c '/usr/bin/uiopen simulafranz-saturimetro://'");
    printf("fine\n");
    return 0;
}
