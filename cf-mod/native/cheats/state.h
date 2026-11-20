#pragma once
#include <jni.h>
#include <atomic>
#include <mutex>
#include <string>
#include <vector>

namespace cf::state {
inline JavaVM *vm = nullptr;

struct Flags {
    std::atomic<bool> esp{false};
    std::atomic<bool> esp_box{true};
    std::atomic<bool> esp_name{true};
    std::atomic<bool> esp_hp{true};
    std::atomic<bool> esp_tracer{false};

    std::atomic<bool> aim{false};
    std::atomic<float> aim_fov{90.f};
    std::atomic<float> aim_smooth{3.5f};
    std::atomic<int>   aim_bone{2}; // 0 head 1 neck 2 chest

    std::atomic<bool> fly{false};
    std::atomic<float> fly_speed{8.f};

    std::atomic<bool> noclip{false};

    std::atomic<bool> killall_armed{false};
    std::atomic<bool> killall_fire{false};

    std::atomic<bool> skin_enabled{false};
    std::atomic<int>  skin_preset{0};

    std::atomic<bool>  god{false};
    std::atomic<bool>  rapid{false};
    std::atomic<bool>  nospread{false};
    std::atomic<bool>  wallbang{false};
    std::atomic<float> speed{1.0f};
};

inline Flags flags;

struct Player {
    void *obj{};
    float px, py, pz;
    float hx, hy, hz;
    float cx, cy, cz;
    float hp{100};
    int   team{0};
    std::string name;
    bool  visible{false};
};

inline std::mutex players_mu;
inline std::vector<Player> players;
inline Player local_player{};

void init();
}
