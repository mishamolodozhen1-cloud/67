// Проверка Luau-кода DUMMY COMBAT (node tools/lint/check.js src):
//   SYNTAX     — файл не разбирается (код пишем без аннотаций типов и `+=`, чтобы его проверял этот разборщик);
//   GLOBALS    — обращение к необъявленной глобальной переменной (опечатка или забытый local);
//   DEPRECATED — устаревший API Roblox (по ТЗ их использовать нельзя).
// Код выхода 1, если есть хоть одна проблема.
const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');

const ALLOWED = new Set([
  // Luau
  'assert', 'error', 'getmetatable', 'ipairs', 'next', 'pairs', 'pcall', 'print', 'rawequal', 'rawget', 'rawlen', 'rawset',
  'require', 'select', 'setmetatable', 'tonumber', 'tostring', 'type', 'typeof', 'unpack', 'xpcall', 'gcinfo',
  'bit32', 'buffer', 'coroutine', 'debug', 'math', 'os', 'string', 'table', 'task', 'utf8', 'vector',
  // Roblox
  'game', 'workspace', 'script', 'plugin', 'shared', 'warn', 'elapsedTime', 'settings', 'UserSettings',
  'Axes', 'BrickColor', 'CatalogSearchParams', 'CFrame', 'Color3', 'ColorSequence', 'ColorSequenceKeypoint', 'Content',
  'DateTime', 'DockWidgetPluginGuiInfo', 'Enum', 'Faces', 'FloatCurveKey', 'Font', 'Instance', 'NumberRange',
  'NumberSequence', 'NumberSequenceKeypoint', 'OverlapParams', 'Path2DControlPoint', 'PathWaypoint', 'PhysicalProperties',
  'Random', 'Ray', 'RaycastParams', 'Rect', 'Region3', 'Region3int16', 'RotationCurveKey', 'SharedTable', 'TweenInfo',
  'UDim', 'UDim2', 'Vector2', 'Vector2int16', 'Vector3', 'Vector3int16',
]);

// [регулярное выражение, что вместо него, 'raw' — искать и внутри строк (имена классов в Instance.new)]
const DEPRECATED = [
  [/(^|[^.:\w])wait\s*\(/, 'wait() → task.wait()'],
  [/(^|[^.:\w])spawn\s*\(/, 'spawn() → task.spawn()'],
  [/(^|[^.:\w])delay\s*\(/, 'delay() → task.delay()'],
  [/(^|[^.:\w])tick\s*\(/, 'tick() → os.clock() / workspace:GetServerTimeNow()'],
  [/(^|[^.:\w])version\s*\(/, 'version() → game.PlaceVersion'],
  [/:connect\s*\(/, ':connect() → :Connect()'],
  [/:disconnect\s*\(/, ':disconnect() → :Disconnect()'],
  [/:Remove\s*\(/, ':Remove() → :Destroy()'],
  [/:isA\s*\(/, ':isA() → :IsA()'],
  [/:findFirstChild\s*\(/, ':findFirstChild() → :FindFirstChild()'],
  [/:children\s*\(/, ':children() → :GetChildren()'],
  [/FindPartOnRay(WithIgnoreList|WithWhitelist)?\s*\(/, 'FindPartOnRay → workspace:Raycast()'],
  [/\bBody(Velocity|Gyro|Position|Force|AngularVelocity|Thrust)\b/, 'Body* movers → LinearVelocity / AlignOrientation / AlignPosition / VectorForce', 'raw'],
  [/\bRocketPropulsion\b/, 'RocketPropulsion → AlignPosition + AlignOrientation', 'raw'],
  [/Humanoid\s*:\s*LoadAnimation|hum\w*\s*:\s*LoadAnimation/, 'Humanoid:LoadAnimation → Animator:LoadAnimation'],
  [/\.Velocity\s*=/, 'BasePart.Velocity → AssemblyLinearVelocity'],
  [/\.RotVelocity\b/, 'BasePart.RotVelocity → AssemblyAngularVelocity'],
  [/:SetPrimaryPartCFrame\s*\(/, ':SetPrimaryPartCFrame → :PivotTo'],
  [/:GetModelCFrame\s*\(/, ':GetModelCFrame → :GetPivot'],
  [/:MakeJoints\s*\(|:BreakJoints\s*\(/, 'MakeJoints/BreakJoints → свои WeldConstraint/Motor6D'],
  [/\bInstance\.new\s*\(\s*"[^"]*"\s*,/, 'Instance.new(класс, родитель) → задать свойства, потом Parent'],
];

let problems = 0;
const seen = [];
function walk(dir) {
  for (const f of fs.readdirSync(dir).sort()) {
    const p = path.join(dir, f);
    if (fs.statSync(p).isDirectory()) walk(p);
    else if (p.endsWith('.lua')) check(p);
  }
}
function stripComments(line) {
  // строки кода без комментариев и строковых литералов (чтобы «wait(» в тексте не считалось)
  return line.replace(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/g, '""').replace(/--.*$/, '');
}
function check(p) {
  const rel = path.relative(process.cwd(), p);
  const src = fs.readFileSync(p, 'utf8');
  let ok = true;
  try {
    const ast = luaparse.parse(src, { luaVersion: '5.2', scope: true, locations: true });
    const globals = [...new Set(ast.globals.map((g) => g.name).filter((n) => !ALLOWED.has(n)))];
    if (globals.length) {
      console.log(`GLOBALS    ${rel}: ${globals.join(', ')}`);
      ok = false;
    }
  } catch (e) {
    console.log(`SYNTAX     ${rel}: ${e.message}`);
    ok = false;
  }
  src.split('\n').forEach((line, i) => {
    const code = stripComments(line);
    const raw = line.replace(/--.*$/, '');
    for (const [re, hint, mode] of DEPRECATED) {
      if (re.test(mode === 'raw' ? raw : code)) {
        console.log(`DEPRECATED ${rel}:${i + 1}: ${hint}`);
        ok = false;
      }
    }
  });
  if (!ok) problems++;
  seen.push(rel);
}
const target = process.argv[2] || 'src';
walk(target);
console.log(`${seen.length} файлов, с проблемами: ${problems}`);
process.exit(problems ? 1 : 0);
