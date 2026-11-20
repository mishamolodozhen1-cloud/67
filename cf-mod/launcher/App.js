import React, { useState, useCallback } from 'react';
import { StatusBar, StyleSheet, Text, View, Pressable, ScrollView, Linking, Alert } from 'react-native';
import * as FileSystem from 'expo-file-system';
import * as Sharing from 'expo-sharing';

const C = {
  bg:    '#12141A',
  bg2:   '#171A22',
  card:  '#1B1E25',
  card2: '#1F232B',
  line:  '#22262E',
  text:  '#E5E5E5',
  muted: '#8A8E94',
  acc:   '#C89B57',
  warn:  '#A76547',
};

const MOD_URL = 'https://github.com/Scratchhhh/counterflame-releases/releases/download/v1.4.1-c7/CounterFlame-1.4.1-c7.apk';

function Row({ title, hint, right }) {
  return (
    <View style={s.row}>
      <View style={{ flex: 1 }}>
        <Text style={s.title}>{title}</Text>
        {hint ? <Text style={s.hint}>{hint}</Text> : null}
      </View>
      {right}
    </View>
  );
}

export default function App() {
  const [status, setStatus] = useState('готов');
  const [progress, setProgress] = useState(0);

  const download = useCallback(async () => {
    try {
      setStatus('скачивание…');
      const path = FileSystem.cacheDirectory + 'CounterFlame-1.4.1-c7-mod.apk';
      const dl = FileSystem.createDownloadResumable(MOD_URL, path, {}, p => {
        setProgress(p.totalBytesWritten / Math.max(1, p.totalBytesExpectedToWrite));
      });
      const r = await dl.downloadAsync();
      setStatus('готов к установке');
      if (await Sharing.isAvailableAsync()) {
        await Sharing.shareAsync(r.uri, { mimeType: 'application/vnd.android.package-archive' });
      }
    } catch (e) {
      Alert.alert('ошибка', String(e));
      setStatus('ошибка');
    }
  }, []);

  return (
    <View style={s.screen}>
      <StatusBar barStyle="light-content" backgroundColor={C.bg} />
      <View style={s.head}>
        <Text style={s.brand}>CF · Bench</Text>
        <Text style={s.ver}>1.4.1-c7</Text>
      </View>

      <ScrollView contentContainerStyle={{ padding: 18 }}>
        <Text style={s.section}>DEPLOY</Text>
        <View style={s.card}>
          <Row title="Скачать модифицированный APK" hint="последняя сборка, подписанная ключом cfmod" right={
            <Pressable onPress={download} style={s.btn}>
              <Text style={s.btnText}>fetch</Text>
            </Pressable>
          }/>
          <View style={s.sep}/>
          <Row title="Открыть страницу игры" hint="counterflame.com" right={
            <Pressable onPress={() => Linking.openURL('https://counterflame.com')} style={s.btnGhost}>
              <Text style={s.btnGhostText}>open</Text>
            </Pressable>
          }/>
          <View style={s.sep}/>
          <Row title="Статус" hint={status} right={
            <Text style={[s.hint, { color: C.acc }]}>{Math.round(progress * 100)}%</Text>
          }/>
        </View>

        <Text style={s.section}>CHEATS</Text>
        <View style={s.card}>
          <Row title="ESP" hint="box · name · hp · tracer" />
          <View style={s.sep}/>
          <Row title="Aim" hint="fov · smooth · head/neck/chest" />
          <View style={s.sep}/>
          <Row title="Fly / Noclip" hint="фиксированная скорость · колайдер off" />
          <View style={s.sep}/>
          <Row title="Skin changer" hint="8 локальных пресетов, без неона" />
          <View style={s.sep}/>
          <Row title="Kill all" hint="arm → fire; шлёт ApplyDamage" />
          <View style={s.sep}/>
          <Row title="God / rapid / no spread / speed / wallbang" hint="вкладка Misc в игровом меню" />
        </View>

        <Text style={s.foot}>built by olivia — https://discord.gg/ojailbreaks</Text>
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: C.bg },
  head: { paddingTop: 44, paddingHorizontal: 22, paddingBottom: 14, backgroundColor: C.bg2,
          borderBottomWidth: 1, borderBottomColor: C.line, flexDirection: 'row', alignItems: 'baseline' },
  brand: { color: C.text, fontSize: 18, fontWeight: '600', letterSpacing: 0.5, flex: 1 },
  ver:   { color: C.muted, fontSize: 12 },
  section:{ color: C.muted, fontSize: 11, letterSpacing: 2, marginTop: 10, marginBottom: 8 },
  card:  { backgroundColor: C.card, borderRadius: 14, paddingVertical: 4, marginBottom: 14 },
  row:   { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 14 },
  title: { color: C.text, fontSize: 15 },
  hint:  { color: C.muted, fontSize: 12, marginTop: 2 },
  sep:   { height: 1, backgroundColor: C.line, marginLeft: 16 },
  btn:   { paddingHorizontal: 16, paddingVertical: 8, borderRadius: 10, backgroundColor: C.acc },
  btnText:{ color: '#12141A', fontWeight: '600' },
  btnGhost:{ paddingHorizontal: 14, paddingVertical: 8, borderRadius: 10, backgroundColor: C.card2 },
  btnGhostText:{ color: C.text },
  foot:  { color: C.muted, fontSize: 11, textAlign: 'center', marginTop: 18, marginBottom: 32 },
});
