// IL2CPP SDK: резолвит экспорты libil2cpp.so и даёт обёртки.
#include "il2cpp.h"
#include "../util/log.h"
#include <dlfcn.h>
#include <string.h>
#include <atomic>

namespace cf::il2cpp {

static void *g_lib = nullptr;
static std::atomic<bool> g_ready{false};

using fn_domain_get = void*(*)();
using fn_thread_attach = void*(*)(void*);
using fn_image_name = const char*(*)(void*);
using fn_domain_images = void**(*)(void*, size_t*);
using fn_class_from_name = void*(*)(void*, const char*, const char*);
using fn_method_from_name = void*(*)(void*, const char*, int);
using fn_field_from_name  = void*(*)(void*, const char*);
using fn_runtime_invoke   = void*(*)(void*, void*, void**, void**);
using fn_field_get_value  = void(*)(void*, void*, void*);
using fn_field_set_value  = void(*)(void*, void*, void*);
using fn_string_chars     = unsigned short*(*)(void*);
using fn_string_length    = int(*)(void*);

static fn_domain_get       p_domain_get;
static fn_thread_attach    p_thread_attach;
static fn_image_name       p_image_name;
static fn_domain_images    p_domain_images;
static fn_class_from_name  p_class_from_name;
static fn_method_from_name p_method_from_name;
static fn_field_from_name  p_field_from_name;
static fn_runtime_invoke   p_runtime_invoke;
static fn_field_get_value  p_field_get_value;
static fn_field_set_value  p_field_set_value;
static fn_string_chars     p_string_chars;
static fn_string_length    p_string_length;

static void *domain = nullptr;

bool attach() {
    if (g_ready.load()) return true;
    g_lib = dlopen("libil2cpp.so", RTLD_NOW);
    if (!g_lib) { CFERR("dlopen libil2cpp.so failed"); return false; }
#define SYM(x, n) p_##x = (fn_##x)dlsym(g_lib, "il2cpp_" n); if (!p_##x) { CFERR("miss %s", n); return false; }
    SYM(domain_get,       "domain_get");
    SYM(thread_attach,    "thread_attach");
    SYM(image_name,       "image_get_name");
    SYM(domain_images,    "domain_get_assemblies");
    SYM(class_from_name,  "class_from_name");
    SYM(method_from_name, "class_get_method_from_name");
    SYM(field_from_name,  "class_get_field_from_name");
    SYM(runtime_invoke,   "runtime_invoke");
    SYM(field_get_value,  "field_get_value");
    SYM(field_set_value,  "field_set_value");
    SYM(string_chars,     "string_chars");
    SYM(string_length,    "string_length");
#undef SYM
    domain = p_domain_get();
    if (!domain) { CFERR("no il2cpp domain"); return false; }
    g_ready = true;
    return true;
}

void attach_thread() { p_thread_attach(domain); }

Img image(const char *name) {
    size_t n = 0;
    void **imgs = p_domain_images(domain, &n);
    for (size_t i = 0; i < n; ++i) {
        const char *nm = p_image_name(imgs[i]);
        if (nm && strstr(nm, name)) return imgs[i];
    }
    return nullptr;
}

Cls klass(Img img, const char *ns, const char *name) {
    if (!img) return nullptr;
    return p_class_from_name(img, ns ? ns : "", name);
}

Method method(Cls c, const char *name, int argc) {
    return c ? p_method_from_name(c, name, argc) : nullptr;
}

Field field(Cls c, const char *name) {
    return c ? p_field_from_name(c, name) : nullptr;
}

void invoke_void(Method m, Obj self, void **argv) {
    if (!m) return;
    void *exc = nullptr;
    p_runtime_invoke(m, self, argv, &exc);
}

Obj invoke_obj(Method m, Obj self, void **argv) {
    if (!m) return nullptr;
    void *exc = nullptr;
    return p_runtime_invoke(m, self, argv, &exc);
}

float invoke_float(Method m, Obj self, void **argv) {
    if (!m) return 0.f;
    void *exc = nullptr;
    void *boxed = p_runtime_invoke(m, self, argv, &exc);
    if (!boxed) return 0.f;
    return *(float*)((char*)boxed + 2 * sizeof(void*));
}

void read_field_raw(Obj o, Field f, void *out, size_t) {
    if (f) p_field_get_value(o, f, out);
}
void write_field_raw(Obj o, Field f, const void *in, size_t) {
    if (f) p_field_set_value(o, f, (void*)in);
}

std::string obj_to_string(Obj s) {
    if (!s || !p_string_chars || !p_string_length) return {};
    int n = p_string_length(s);
    unsigned short *w = p_string_chars(s);
    std::string out; out.reserve(n);
    for (int i = 0; i < n; ++i) out.push_back((char)(w[i] & 0xFF));
    return out;
}

}
