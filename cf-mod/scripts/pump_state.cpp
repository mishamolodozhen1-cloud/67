// Отдельный pump — собирается внутри libcfcheat и крутится в фоне.
#include "../native/cheats/state.h"
#include "../native/hooks/il2cpp.h"
#include "../native/util/world.h"
#include "../native/util/log.h"
#include <thread>
#include <chrono>

namespace cf::pump {

static void fill_from_object(void *obj, cf::state::Player &p) { (void)obj; (void)p; }

void run() {
    using namespace std::chrono_literals;
    while (!cf::il2cpp::attach()) std::this_thread::sleep_for(500ms);
    cf::il2cpp::attach_thread();

    auto img       = cf::il2cpp::image("Assembly-CSharp");
    auto cls_match = cf::il2cpp::klass(img, "CF.Match", "MatchSession");
    auto m_players = cf::il2cpp::method(cls_match, "GetPlayers", 0);
    auto m_instance= cf::il2cpp::method(cls_match, "get_Instance", 0);
    auto m_local   = cf::il2cpp::method(cls_match, "GetLocalPlayer", 0);

    while (true) {
        std::this_thread::sleep_for(16ms);
        if (!m_instance) continue;
        void *ses = cf::il2cpp::invoke_obj(m_instance, nullptr, nullptr);
        if (!ses) continue;
        void *lp  = cf::il2cpp::invoke_obj(m_local, ses, nullptr);
        cf::state::local_player.obj = lp;
        void *arr = cf::il2cpp::invoke_obj(m_players, ses, nullptr);
        if (!arr) continue;
        int32_t len  = *(int32_t*)((char*)arr + sizeof(void*) * 2);
        void **items = (void**)((char*)arr + sizeof(void*) * 4);
        std::lock_guard<std::mutex> lk(cf::state::players_mu);
        cf::state::players.resize(len);
        for (int i = 0; i < len; ++i) {
            auto &p = cf::state::players[i];
            p.obj = items[i];
            fill_from_object(items[i], p);
        }
    }
}
}
