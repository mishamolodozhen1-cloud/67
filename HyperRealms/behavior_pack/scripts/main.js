import { world, system } from "@minecraft/server";

// Hyper Realms - ambient life for the new biomes.
// Every entry: particle id, how many per pulse by day / by night, and the box
// around the player (horizontal radius, lowest and highest offset) to fill.
const AMBIENT = {
  "hyper:glowwood_forest": { particle: "hyper:firefly", day: 3, night: 9, radius: 14, low: -1, high: 6 },
  "hyper:emerald_highlands": { particle: "hyper:firefly", day: 0, night: 5, radius: 14, low: 0, high: 5 },
  "hyper:autumn_woods": { particle: "hyper:falling_leaf", day: 6, night: 3, radius: 12, low: 3, high: 9 },
  "hyper:crystal_fields": { particle: "hyper:crystal_mote", day: 2, night: 7, radius: 13, low: 0, high: 4 },
  "hyper:titan_peaks": { particle: "hyper:snow_glint", day: 6, night: 3, radius: 14, low: 0, high: 8 },
  "hyper:frostfang_slopes": { particle: "hyper:snow_glint", day: 7, night: 4, radius: 14, low: 0, high: 8 },
  "hyper:sunset_crags": { particle: "hyper:ember_dust", day: 4, night: 2, radius: 14, low: 0, high: 7 },
};

const PULSE_TICKS = 10;
const lastBiome = new Map();

function between(min, max) {
  return min + Math.random() * (max - min);
}

function isNight() {
  const time = world.getTimeOfDay();
  return time > 12800 && time < 23200;
}

function biomeIdAt(player) {
  try {
    return player.dimension.getBiome(player.location).id;
  } catch {
    return undefined;
  }
}

function pulse(player, night) {
  if (player.dimension.id !== "minecraft:overworld") return;
  const biomeId = biomeIdAt(player);
  if (biomeId === undefined) return;

  if (lastBiome.get(player.id) !== biomeId) {
    lastBiome.set(player.id, biomeId);
    if (biomeId in AMBIENT) {
      player.onScreenDisplay.setActionBar({ translate: `hyper.biome.${biomeId.split(":")[1]}` });
    }
  }

  const ambient = AMBIENT[biomeId];
  if (!ambient) return;
  const count = night ? ambient.night : ambient.day;
  const { x, y, z } = player.location;
  for (let i = 0; i < count; i++) {
    const spot = {
      x: x + between(-ambient.radius, ambient.radius),
      y: y + between(ambient.low, ambient.high),
      z: z + between(-ambient.radius, ambient.radius),
    };
    try {
      player.spawnParticle(ambient.particle, spot);
    } catch {
      // Outside the loaded world - skip this one.
    }
  }
}

system.runInterval(() => {
  const night = isNight();
  for (const player of world.getAllPlayers()) {
    try {
      pulse(player, night);
    } catch {
      // The player left mid-tick.
    }
  }
}, PULSE_TICKS);

world.afterEvents.playerSpawn.subscribe((event) => {
  if (event.initialSpawn) {
    event.player.sendMessage({ translate: "hyper.welcome" });
  }
});

world.afterEvents.playerLeave.subscribe((event) => {
  lastBiome.delete(event.playerId);
});
