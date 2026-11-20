#pragma once
#include <cstdint>
#include <string>

namespace cf::il2cpp {

using Img = void*;
using Cls = void*;
using Method = void*;
using Field = void*;
using Obj = void*;

bool attach();   // dlopen libil2cpp.so, resolve symbol table

Img  image(const char *name);
Cls  klass(Img img, const char *ns, const char *name);
Method method(Cls c, const char *name, int argc);
Field  field(Cls c, const char *name);

void   invoke_void(Method m, Obj self, void **argv);
Obj    invoke_obj(Method m, Obj self, void **argv);
float  invoke_float(Method m, Obj self, void **argv);

template <typename T>
T read_field(Obj o, Field f) {
    T v{}; read_field_raw(o, f, &v, sizeof(T)); return v;
}
template <typename T>
void write_field(Obj o, Field f, const T &v) {
    write_field_raw(o, f, &v, sizeof(T));
}
void read_field_raw(Obj, Field, void*, size_t);
void write_field_raw(Obj, Field, const void*, size_t);

void attach_thread();

std::string obj_to_string(Obj);
}
