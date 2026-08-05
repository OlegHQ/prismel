let escape_html value =
  let output = Buffer.create (String.length value) in
  String.iter
    (function
      | '&' -> Buffer.add_string output "&amp;"
      | '<' -> Buffer.add_string output "&lt;"
      | '>' -> Buffer.add_string output "&gt;"
      | '"' -> Buffer.add_string output "&quot;"
      | '\'' -> Buffer.add_string output "&#39;"
      | character -> Buffer.add_char output character)
    value;
  Buffer.contents output

let page ~title ~token ~resizable =
  let title = escape_html title and token = escape_html token in
  String.concat "" [
    "<!doctype html><html><head><meta charset=\"utf-8\">";
    "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1,viewport-fit=cover,interactive-widget=overlays-content\">";
    "<title>"; title; "</title><style>";
    "html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#090b10;color:#dce7f5;font:13px system-ui,sans-serif}";
    "body{position:fixed;inset:0}canvas{position:fixed;inset:0;display:block;outline:none;touch-action:none;image-rendering:auto}";
    "#status{position:fixed;left:10px;top:8px;padding:4px 7px;border-radius:4px;background:#111a;color:#fff;pointer-events:none}";
    "#ime{position:fixed;left:-100px;top:0;width:20px;height:20px;z-index:2;margin:0;padding:0;border:0;outline:0;opacity:.01;color:transparent;background:transparent;caret-color:transparent;pointer-events:none;resize:none;font-size:16px}";
    "</style></head><body><canvas id=\"prismel\" tabindex=\"0\" data-token=\"";
    token; "\" data-resizable=\""; (if resizable then "1" else "0");
    "\"></canvas><div id=\"status\">connecting…</div>";
    "<textarea id=\"ime\" inputmode=\"text\" enterkeyhint=\"done\" autocomplete=\"off\" autocorrect=\"on\" autocapitalize=\"sentences\" spellcheck=\"true\" aria-label=\"Prismel text input\"></textarea>";
    "<script src=\"/client.js\"></script></body></html>";
  ]

let script = {|
(() => {
  "use strict";
  const canvas = document.getElementById("prismel");
  const ime = document.getElementById("ime");
  const status = document.getElementById("status");
  const encoder = new TextEncoder();
  let logicalWidth = 1, logicalHeight = 1;
  let viewportWidth = 1, viewportHeight = 1;
  let drawableWidth = 0, drawableHeight = 0;
  let decodedPixels = null;
  let gl = null, context2d = null, texture = null, program = null;
  let connected = false;
  let masterVolume = 1, musicVolume = 1, music = null;
  let textInputRegions = [], composing = false, imeSnapshot = "";
  let activeTextInputRegion = null;
  let pendingTextFocus = false, confirmedTextFocus = false;
  const channels = new Map(), pendingAudio = new Set();
  const capturedButtons = new Map();
  const qoiIndex = new Uint8Array(64 * 4);

  function setStatus(text) {
    status.textContent = text;
    status.style.display = text ? "block" : "none";
  }

  function compileShader(type, source) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS))
      throw new Error(gl.getShaderInfoLog(shader));
    return shader;
  }

  function initializeWebGL() {
    gl = canvas.getContext("webgl2", {
      alpha: false, antialias: true, depth: false, stencil: false,
      preserveDrawingBuffer: false, powerPreference: "high-performance"
    }) || canvas.getContext("webgl", {
      alpha: false, antialias: true, depth: false, stencil: false,
      preserveDrawingBuffer: false, powerPreference: "high-performance"
    });
    if (!gl) {
      context2d = canvas.getContext("2d", {alpha: false});
      return;
    }
    const vertex = compileShader(gl.VERTEX_SHADER,
      "attribute vec2 p; varying vec2 uv; void main(){gl_Position=vec4(p,0.,1.);uv=vec2((p.x+1.)*.5,(1.-p.y)*.5);}");
    const fragment = compileShader(gl.FRAGMENT_SHADER,
      "precision mediump float; varying vec2 uv; uniform sampler2D frame; void main(){gl_FragColor=texture2D(frame,uv);}");
    program = gl.createProgram();
    gl.attachShader(program, vertex); gl.attachShader(program, fragment);
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS))
      throw new Error(gl.getProgramInfoLog(program));
    gl.useProgram(program);
    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 1,-1, -1,1, 1,1]), gl.STATIC_DRAW);
    const location = gl.getAttribLocation(program, "p");
    gl.enableVertexAttribArray(location);
    gl.vertexAttribPointer(location, 2, gl.FLOAT, false, 0, 0);
    texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
  }

  function fitCanvas() {
    canvas.style.width = viewportWidth + "px";
    canvas.style.height = viewportHeight + "px";
  }

  function measureViewport() {
    return [
      Math.max(1, Math.round(document.documentElement.clientWidth || innerWidth)),
      Math.max(1, Math.round(document.documentElement.clientHeight || innerHeight))
    ];
  }

  function positionIme(region = activeTextInputRegion) {
    if (!region || logicalWidth < 1 || logicalHeight < 1) {
      ime.style.left = "-100px";
      return;
    }
    const rect = canvas.getBoundingClientRect();
    const left = rect.left + region[0] * rect.width / logicalWidth;
    const top = rect.top + region[1] * rect.height / logicalHeight;
    const width = Math.max(20, region[2] * rect.width / logicalWidth);
    const height = Math.max(20, region[3] * rect.height / logicalHeight);
    ime.style.left = left + "px"; ime.style.top = top + "px";
    ime.style.width = width + "px"; ime.style.height = height + "px";
  }

  function decodeQoi(encoded, output) {
    const index = qoiIndex;
    index.fill(0);
    let source = 0, target = 0;
    let r = 0, g = 0, b = 0, a = 255;
    while (target < output.length) {
      if (source >= encoded.length) return false;
      const opcode = encoded[source++];
      if (opcode === 0xfe) {
        if (source + 3 > encoded.length) return false;
        r = encoded[source++]; g = encoded[source++]; b = encoded[source++];
      } else if (opcode === 0xff) {
        if (source + 4 > encoded.length) return false;
        r = encoded[source++]; g = encoded[source++]; b = encoded[source++];
        a = encoded[source++];
      } else {
        switch (opcode & 0xc0) {
          case 0x00: {
            const slot = (opcode & 63) * 4;
            r = index[slot]; g = index[slot + 1];
            b = index[slot + 2]; a = index[slot + 3];
            break;
          }
          case 0x40:
            r = (r + ((opcode >> 4 & 3) - 2)) & 255;
            g = (g + ((opcode >> 2 & 3) - 2)) & 255;
            b = (b + ((opcode & 3) - 2)) & 255;
            break;
          case 0x80: {
            if (source >= encoded.length) return false;
            const next = encoded[source++], green = (opcode & 63) - 32;
            r = (r + green + ((next >> 4) - 8)) & 255;
            g = (g + green) & 255;
            b = (b + green + ((next & 15) - 8)) & 255;
            break;
          }
          case 0xc0: {
            const count = (opcode & 63) + 1;
            if (target + count * 4 > output.length) return false;
            for (let run = 0; run < count; run++) {
              output[target++] = r; output[target++] = g;
              output[target++] = b; output[target++] = a;
            }
            continue;
          }
        }
      }
      const slot = ((r * 3 + g * 5 + b * 7 + a * 11) & 63) * 4;
      index[slot] = r; index[slot + 1] = g;
      index[slot + 2] = b; index[slot + 3] = a;
      output[target++] = r; output[target++] = g;
      output[target++] = b; output[target++] = a;
    }
    return source === encoded.length;
  }

  function present(buffer) {
    const view = new DataView(buffer);
    if (buffer.byteLength < 28 || view.getUint32(0, false) !== 0x5052534d ||
        view.getUint16(4, true) !== 1) return;
    const codec = view.getUint16(6, true), frameId = view.getUint32(8, true);
    const width = view.getUint32(12, true), height = view.getUint32(16, true);
    const nextLogicalWidth = view.getUint32(20, true);
    const nextLogicalHeight = view.getUint32(24, true);
    const patch = codec >= 2, compressed = (codec & 1) === 1;
    const headerBytes = patch ? 44 : 28;
    if (buffer.byteLength < headerBytes || codec > 3) return false;
    const patchX = patch ? view.getUint32(28, true) : 0;
    const patchY = patch ? view.getUint32(32, true) : 0;
    const patchWidth = patch ? view.getUint32(36, true) : width;
    const patchHeight = patch ? view.getUint32(40, true) : height;
    const pixelBytes = patchWidth * patchHeight * 4;
    const required = headerBytes + pixelBytes;
    if (!width || !height || !nextLogicalWidth || !nextLogicalHeight ||
        !patchWidth || !patchHeight || patchX + patchWidth > width ||
        patchY + patchHeight > height ||
        (!compressed && buffer.byteLength !== required) ||
        (compressed && buffer.byteLength <= headerBytes)) return false;
    const drawableSizeChanged = width !== drawableWidth || height !== drawableHeight;
    if (patch && drawableSizeChanged) return false;
    const logicalSizeChanged = nextLogicalWidth !== logicalWidth ||
      nextLogicalHeight !== logicalHeight;
    logicalWidth = nextLogicalWidth; logicalHeight = nextLogicalHeight;
    let pixels;
    if (!compressed) pixels = new Uint8Array(buffer, headerBytes);
    else {
      if (!decodedPixels || decodedPixels.length !== pixelBytes)
        decodedPixels = new Uint8Array(pixelBytes);
      if (!decodeQoi(new Uint8Array(buffer, headerBytes), decodedPixels)) return false;
      pixels = decodedPixels;
    }
    if (drawableSizeChanged) {
      drawableWidth = width; drawableHeight = height;
      canvas.width = width; canvas.height = height;
      if (gl) {
        gl.viewport(0, 0, width, height);
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0,
          gl.RGBA, gl.UNSIGNED_BYTE, pixels);
      }
    } else if (gl) {
      gl.bindTexture(gl.TEXTURE_2D, texture);
      gl.texSubImage2D(gl.TEXTURE_2D, 0, patchX, patchY,
        patchWidth, patchHeight,
        gl.RGBA, gl.UNSIGNED_BYTE, pixels);
    }
    if (logicalSizeChanged || !canvas.style.width) {
      fitCanvas();
      positionIme();
    }
    if (gl) gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    else context2d.putImageData(
      new ImageData(
        new Uint8ClampedArray(pixels.buffer, pixels.byteOffset, pixels.byteLength),
        patchWidth, patchHeight), patchX, patchY);
    if (!connected) { connected = true; setStatus(""); }
    send(13,[frameId]);
    return true;
  }

  const scheme = location.protocol === "https:" ? "wss:" : "ws:";
  const socket = new WebSocket(scheme + "//" + location.host + "/ws?token=" +
    encodeURIComponent(canvas.dataset.token));
  socket.binaryType = "arraybuffer";
  socket.onopen = () => setStatus("waiting for first frame…");
  const assetUrl = id => "/asset/" + encodeURIComponent(id) + "?token=" +
    encodeURIComponent(canvas.dataset.token);
  function startAudio(audio) {
    const promise = audio.play();
    if (promise) promise.catch(() => pendingAudio.add(audio));
  }
  function stopAudio(audio) {
    audio.pause();
    try { audio.currentTime = 0; } catch (_) {}
    pendingAudio.delete(audio);
  }
  function fade(audio, from, to, milliseconds, done) {
    const started = performance.now();
    audio.volume = Math.max(0, Math.min(1, from));
    function step(now) {
      const amount = milliseconds <= 0 ? 1 : Math.min(1, (now - started) / milliseconds);
      audio.volume = Math.max(0, Math.min(1, from + (to - from) * amount));
      if (amount < 1) requestAnimationFrame(step); else if (done) done();
    }
    requestAnimationFrame(step);
  }
  function resetImeProxy() {
    ime.value = "";
    imeSnapshot = "";
    composing = false;
  }
  function setTextInputRegions(command) {
    if (!Array.isArray(command.regions)) return;
    textInputRegions = command.regions.filter(region =>
      Array.isArray(region) && region.length === 5 &&
      region.slice(0, 4).every(Number.isFinite) &&
      region[2] > 0 && region[3] > 0);
    const focusedRegion = textInputRegions.find(region => region[4]);
    if (focusedRegion) {
      activeTextInputRegion = focusedRegion;
      positionIme();
      pendingTextFocus = false;
      confirmedTextFocus = true;
    }
    if (textInputRegions.length === 0 && document.activeElement === ime) {
      pendingTextFocus = false; confirmedTextFocus = false;
      activeTextInputRegion = null;
      ime.blur(); resetImeProxy(); positionIme();
    } else if (!focusedRegion && confirmedTextFocus &&
               !pendingTextFocus && document.activeElement === ime) {
      confirmedTextFocus = false;
      activeTextInputRegion = null;
      ime.blur(); resetImeProxy(); positionIme();
    }
  }
  function downloadFrame(command) {
    if (!drawableWidth || !drawableHeight || typeof command.filename !== "string") {
      setStatus("PNG download unavailable");
      return;
    }
    // WebGL may discard its drawing buffer after presentation. The texture is
    // retained, so draw it once more immediately before browser-side encoding.
    if (gl) gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    canvas.toBlob(blob => {
      if (!blob) { setStatus("PNG download failed"); return; }
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url; link.download = command.filename;
      link.style.display = "none";
      document.body.appendChild(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    }, "image/png");
  }
  function handleCommand(command) {
    switch (command.op) {
      case "text_input_regions": setTextInputRegions(command); break;
      case "download_frame": downloadFrame(command); break;
      case "master_volume":
        masterVolume = command.volume;
        channels.forEach(audio => audio.volume = Math.max(0, Math.min(1,
          Number(audio.dataset.volume) * masterVolume)));
        if (music) music.volume = Math.max(0, Math.min(1, musicVolume * masterVolume));
        break;
      case "stop_all":
        channels.forEach(stopAudio); channels.clear();
        if (music) { stopAudio(music); music = null; }
        break;
      case "sample_play": {
        const previous = channels.get(command.channel);
        if (previous) stopAudio(previous);
        const audio = new Audio(assetUrl(command.id));
        audio.preload = "auto"; audio.dataset.asset = command.id;
        audio.dataset.volume = command.volume;
        audio.volume = Math.max(0, Math.min(1, command.volume * masterVolume));
        let remaining = command.loops;
        audio.loop = remaining < 0;
        audio.addEventListener("ended", () => {
          if (remaining > 0) { remaining--; audio.currentTime = 0; startAudio(audio); }
          else channels.delete(command.channel);
        });
        channels.set(command.channel, audio); startAudio(audio);
        break;
      }
      case "sample_volume":
        channels.forEach(audio => {
          if (audio.dataset.asset === command.id) {
            audio.dataset.volume = command.volume;
            audio.volume = Math.max(0, Math.min(1, command.volume * masterVolume));
          }
        });
        break;
      case "sample_stop": { const audio = channels.get(command.channel); if (audio) stopAudio(audio); channels.delete(command.channel); break; }
      case "sample_pause": { const audio = channels.get(command.channel); if (audio) audio.pause(); break; }
      case "sample_resume": { const audio = channels.get(command.channel); if (audio) startAudio(audio); break; }
      case "asset_remove":
        channels.forEach((audio, channel) => { if (audio.dataset.asset === command.id) { stopAudio(audio); channels.delete(channel); } });
        if (music && music.dataset.asset === command.id) { stopAudio(music); music = null; }
        break;
      case "music_play": {
        if (music) stopAudio(music);
        music = new Audio(assetUrl(command.id)); music.preload = "auto";
        music.dataset.asset = command.id; music.loop = command.loops < 0;
        let remaining = command.loops;
        music.addEventListener("ended", () => {
          if (remaining > 0) { remaining--; music.currentTime = 0; startAudio(music); }
        });
        const target = Math.max(0, Math.min(1, musicVolume * masterVolume));
        if (command.fade > 0) { music.volume = 0; startAudio(music); fade(music, 0, target, command.fade); }
        else { music.volume = target; startAudio(music); }
        break;
      }
      case "music_volume":
        musicVolume = command.volume;
        if (music) music.volume = Math.max(0, Math.min(1, musicVolume * masterVolume));
        break;
      case "music_pause": if (music) music.pause(); break;
      case "music_resume": if (music) startAudio(music); break;
      case "music_stop":
        if (music) {
          const stopped = music;
          if (command.fade > 0) fade(stopped, stopped.volume, 0, command.fade,
            () => { stopAudio(stopped); if (music === stopped) music = null; });
          else { stopAudio(stopped); music = null; }
        }
        break;
    }
  }
  let pendingFrame = null, framePresentationScheduled = false;
  function scheduleFramePresentation() {
    if (framePresentationScheduled) return;
    framePresentationScheduled = true;
    requestAnimationFrame(() => {
      framePresentationScheduled = false;
      const frame = pendingFrame;
      pendingFrame = null;
      if (frame) present(frame);
      if (pendingFrame) scheduleFramePresentation();
    });
  }
  socket.onmessage = event => {
    if (event.data instanceof ArrayBuffer) {
      pendingFrame = event.data;
      scheduleFramePresentation();
    } else try { handleCommand(JSON.parse(event.data)); } catch (_) {}
  };
  socket.onerror = () => setStatus("web connection failed");
  socket.onclose = () => { connected = false; setStatus("disconnected"); };

  function send(opcode, integers = [], text = "") {
    if (socket.readyState !== WebSocket.OPEN) return;
    const encoded = encoder.encode(text);
    const bytes = new Uint8Array(2 + integers.length * 4 + encoded.length);
    const view = new DataView(bytes.buffer);
    bytes[0] = 1; bytes[1] = opcode;
    integers.forEach((value, index) => view.setInt32(2 + index * 4, value, true));
    bytes.set(encoded, 2 + integers.length * 4);
    socket.send(bytes);
  }

  function point(event) {
    const rect = canvas.getBoundingClientRect();
    if (!(rect.width > 0) || !(rect.height > 0)) return [0, 0];
    return [
      Math.floor((event.clientX - rect.left) * logicalWidth / rect.width),
      Math.floor((event.clientY - rect.top) * logicalHeight / rect.height)
    ];
  }
  function textInputAt(x, y) {
    return textInputRegions.find(region =>
      x >= region[0] && x < region[0] + region[2] &&
      y >= region[1] && y < region[1] + region[3]);
  }
  function focusWithoutScroll(element) {
    try { element.focus({preventScroll:true}); }
    catch (_) { element.focus(); }
  }
  const button = value => value === 0 ? 1 : value === 1 ? 2 : value === 2 ? 3 : value === 3 ? 4 : 5;
  canvas.addEventListener("pointermove", event => {
    const coalesced = typeof event.getCoalescedEvents === "function"
      ? event.getCoalescedEvents() : [];
    const samples = coalesced.length ? coalesced : [event];
    const integers = [];
    const first = Math.max(0, samples.length - 64);
    let previousX = null, previousY = null;
    for (let index = first; index < samples.length; index++) {
      const [x,y] = point(samples[index]);
      if (x !== previousX || y !== previousY) {
        integers.push(x,y); previousX = x; previousY = y;
      }
    }
    if (integers.length) send(1,integers);
  });
  canvas.addEventListener("pointerdown", event => {
    pendingAudio.forEach(audio => startAudio(audio)); pendingAudio.clear();
    const [x,y] = point(event), pressed = button(event.button);
    capturedButtons.set(event.pointerId, pressed);
    const textRegion = textInputAt(x, y);
    if (textRegion) {
      pendingTextFocus = true;
      activeTextInputRegion = textRegion;
      resetImeProxy();
      positionIme();
      focusWithoutScroll(ime);
    } else {
      pendingTextFocus = false; confirmedTextFocus = false;
      activeTextInputRegion = null;
      resetImeProxy(); ime.blur(); positionIme(); focusWithoutScroll(canvas);
    }
    event.preventDefault(); canvas.setPointerCapture(event.pointerId);
    send(2,[pressed,x,y]);
  });
  canvas.addEventListener("pointerup", event => {
    event.preventDefault(); const [x,y] = point(event);
    const released = capturedButtons.get(event.pointerId) || button(event.button);
    capturedButtons.delete(event.pointerId); send(3,[released,x,y]);
    if (canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
  });
  canvas.addEventListener("pointercancel", event => {
    const cancelled = capturedButtons.get(event.pointerId);
    capturedButtons.delete(event.pointerId);
    if (cancelled) send(12,[cancelled]);
    if (canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
  });
  canvas.addEventListener("contextmenu", event => event.preventDefault());
  canvas.addEventListener("wheel", event => {
    event.preventDefault(); send(4,[-Math.sign(event.deltaX),-Math.sign(event.deltaY)]);
  }, {passive:false});

  const keyName = event => event.key.length === 1 ? event.key.toLowerCase() : event.key;
  window.addEventListener("keydown", event => {
    if (event.repeat || event.isComposing) return;
    const editing = document.activeElement === ime;
    const key = keyName(event);
    if (!(editing && event.key === "Backspace")) send(5,[],key);
    if (!editing && event.key.length === 1 &&
        !event.ctrlKey && !event.metaKey && !event.altKey)
      send(7,[],event.key);
    if (!editing && ["ArrowUp","ArrowDown","ArrowLeft","ArrowRight"," ","Tab","Backspace"].includes(event.key))
      event.preventDefault();
  });
  window.addEventListener("keyup", event => {
    if (!event.isComposing &&
        !(document.activeElement === ime && event.key === "Backspace"))
      send(6,[],keyName(event));
  });
  function sendBackspaces(count) {
    for (let index = 0; index < count; index++) {
      send(5,[],"Backspace"); send(6,[],"Backspace");
    }
  }
  function synchronizeImeValue() {
    const before = Array.from(imeSnapshot), after = Array.from(ime.value);
    let prefix = 0;
    while (prefix < before.length && prefix < after.length &&
           before[prefix] === after[prefix]) prefix++;
    // PXUI currently edits at the end of its value. Rebuild the complete
    // changed proxy suffix so autocorrect replacements in the middle remain
    // correct without requiring a remote cursor protocol.
    sendBackspaces(before.length - prefix);
    const inserted = after.slice(prefix).join("");
    if (inserted) send(7,[],inserted);
    imeSnapshot = ime.value;
    if (after.length > 1024) {
      const tail = after.slice(-256).join("");
      ime.value = tail; imeSnapshot = tail;
    }
  }
  ime.addEventListener("compositionstart", () => { composing = true; });
  ime.addEventListener("compositionupdate", event => {
    const text = event.data || "";
    send(8,[0,text.length],text);
  });
  ime.addEventListener("compositionend", () => {
    composing = false;
    send(8,[0,0],"");
    setTimeout(synchronizeImeValue, 0);
  });
  ime.addEventListener("input", event => {
    if (event.isComposing || composing) return;
    synchronizeImeValue();
  });
  window.addEventListener("blur", () => send(10));

  canvas.addEventListener("dragover", event => event.preventDefault());
  canvas.addEventListener("drop", async event => {
    event.preventDefault();
    for (const file of event.dataTransfer.files) {
      const name = encoder.encode(file.name);
      if (!name.length || name.length > 1024 || file.size > 16 * 1024 * 1024) {
        setStatus("dropped file exceeds the 16 MiB web limit");
        continue;
      }
      const contents = new Uint8Array(await file.arrayBuffer());
      const message = new Uint8Array(4 + name.length + contents.length);
      const view = new DataView(message.buffer);
      message[0] = 1; message[1] = 11;
      view.setUint16(2, name.length, true);
      message.set(name, 4); message.set(contents, 4 + name.length);
      if (socket.readyState === WebSocket.OPEN) socket.send(message);
    }
  });

  let resizeTimer = 0;
  function sendResize() {
    if (document.activeElement === ime) return;
    ([viewportWidth, viewportHeight] = measureViewport());
    fitCanvas();
    if (canvas.dataset.resizable !== "1") return;
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => {
      if (document.activeElement !== ime)
        send(9,[viewportWidth,viewportHeight]);
    }, 50);
  }
  ime.addEventListener("blur", () => {
    if (!composing) synchronizeImeValue();
    pendingTextFocus = false;
    resetImeProxy();
    setTimeout(sendResize, 100);
  });
  window.addEventListener("resize", sendResize);
  window.addEventListener("orientationchange", sendResize);
  if (window.visualViewport)
    window.visualViewport.addEventListener("resize", sendResize);
  socket.addEventListener("open", sendResize);
  ([viewportWidth, viewportHeight] = measureViewport());
  fitCanvas();
  initializeWebGL();
})();
|}
