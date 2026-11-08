// similFranzSat — generatore di QR code minimo (C puro: iOS 6 non ha CIQRCodeGenerator).
// Modalità byte, correzione d'errore M, versioni 1-10 (fino a 213 byte), maschera scelta per penalità.
#include <stdint.h>
#include <stdbool.h>

#define SFQR_MAX_SIZE 57   // versione 10

// Codifica `text` (len byte). Riempie modules[y * size + x] (1 = nero) e *size. Ritorna false se il testo è troppo lungo.
bool SFQREncode(const uint8_t *text, int len, uint8_t modules[SFQR_MAX_SIZE * SFQR_MAX_SIZE], int *size);
