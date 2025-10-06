#include "duckdb/duckdb_stable.hpp"

using namespace duckdb_stable;

struct QuackOp {
    static string_t Operation(const string_t& name) {
        std::string name_str(name.GetData(), name.GetSize());
        std::string result = FormatUtil::Format("Quack {} 🐥", {name_str});

        char* data = (char*)duckdb_malloc(result.size());
        memcpy(data, result.c_str(), result.size());

        return string_t(data, result.size());
    }
};

class QuackFunction : public UnaryFunction<QuackOp, PrimitiveType<string_t>, PrimitiveType<string_t>> {
   public:
    const char* Name() const override {
        return "quack";
    }
};

DUCKDB_EXTENSION_CPP_ENTRYPOINT(Quack) {
    QuackFunction quack_func;
    Register(quack_func);
}
