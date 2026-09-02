#include "include/CArchive.h"
#include "miniz.h"
#include <stdlib.h>
#include <string.h>
void *eg_zip_open(const void *bytes, size_t size) {
    mz_zip_archive *z = (mz_zip_archive *)calloc(1, sizeof(mz_zip_archive));
    if (!z) return NULL;
    if (!mz_zip_reader_init_mem(z, bytes, size, 0)) { free(z); return NULL; }
    return z;
}
unsigned eg_zip_count(void *reader) { return mz_zip_reader_get_num_files((mz_zip_archive *)reader); }
int eg_zip_stat(void *reader, unsigned index, char *name, size_t cap, uint64_t *expanded, uint64_t *compressed) {
    mz_zip_archive *z = (mz_zip_archive *)reader;
    mz_zip_archive_file_stat s;
    if (!mz_zip_reader_file_stat(z, index, &s) || s.m_is_encrypted || !s.m_is_supported || s.m_is_directory) return 0;
    unsigned need = mz_zip_reader_get_filename(z, index, NULL, 0);
    if (!need || need > cap) return 0;
    if (mz_zip_reader_get_filename(z, index, name, (unsigned)cap) != need) return 0;
    *expanded = s.m_uncomp_size; *compressed = s.m_comp_size;
    return 1;
}
void *eg_zip_extract(void *reader, unsigned index, size_t *size) { return mz_zip_reader_extract_to_heap((mz_zip_archive *)reader, index, size, 0); }
void eg_zip_close(void *reader) { if (reader) { mz_zip_reader_end((mz_zip_archive *)reader); free(reader); } }
void eg_zip_free(void *bytes) { mz_free(bytes); }
void *eg_zip_writer(void) {
    mz_zip_archive *z = (mz_zip_archive *)calloc(1, sizeof(mz_zip_archive));
    if (!z) return NULL;
    if (!mz_zip_writer_init_heap(z, 0, 0)) { free(z); return NULL; }
    return z;
}
int eg_zip_add(void *writer, const char *name, const void *bytes, size_t size) { return mz_zip_writer_add_mem((mz_zip_archive *)writer, name, bytes, size, MZ_DEFAULT_COMPRESSION); }
void *eg_zip_finish(void *writer, size_t *size) {
    void *bytes = NULL;
    int ok = mz_zip_writer_finalize_heap_archive((mz_zip_archive *)writer, &bytes, size);
    mz_zip_writer_end((mz_zip_archive *)writer); free(writer);
    return ok ? bytes : NULL;
}
void eg_zip_abort(void *writer) { if (writer) { mz_zip_writer_end((mz_zip_archive *)writer); free(writer); } }
