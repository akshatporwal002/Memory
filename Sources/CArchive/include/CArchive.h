#ifndef ENGRAM_ARCHIVE_H
#define ENGRAM_ARCHIVE_H
#include <stddef.h>
#include <stdint.h>
void *eg_zip_open(const void *bytes, size_t size);
unsigned eg_zip_count(void *reader);
int eg_zip_stat(void *reader, unsigned index, char *name, size_t name_size, uint64_t *expanded, uint64_t *compressed);
void *eg_zip_extract(void *reader, unsigned index, size_t *size);
void eg_zip_close(void *reader);
void eg_zip_free(void *bytes);
void *eg_zip_writer(void);
int eg_zip_add(void *writer, const char *name, const void *bytes, size_t size);
void *eg_zip_finish(void *writer, size_t *size);
void eg_zip_abort(void *writer);
#endif
