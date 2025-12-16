--- C++ language actions with enhanced autodetection
local M = {}
local pkg_cache = {}

local function get_pkg_config_flags(lib)
  if pkg_cache[lib] ~= nil then return pkg_cache[lib] end
  local handle = io.popen("pkg-config --cflags --libs " .. lib .. " 2>/dev/null")
  if not handle then pkg_cache[lib] = false return nil end
  local flags = handle:read("*a"):gsub("\n", "")
  handle:close()
  pkg_cache[lib] = flags ~= "" and flags or false
  return pkg_cache[lib]
end

local function check_pkg_config(lib)
  if pkg_cache[lib] ~= nil then return pkg_cache[lib] ~= false end
  local handle = io.popen("pkg-config --exists " .. lib .. " 2>/dev/null && echo 'yes'")
  if not handle then pkg_cache[lib] = false return false end
  local exists = handle:read("*a"):match("yes") ~= nil
  handle:close()
  if not exists then pkg_cache[lib] = false end
  return exists
end

local function scan_includes(files)
  local includes, seen = {}, {}
  for file in files:gmatch("[^%s]+") do
    file = file:gsub('"', '')
    if not seen[file] then
      seen[file] = true
      local f = io.open(file, "r")
      if f then
        for line in f:lines() do
          local inc = line:match('#include%s*[<"]([^>"]+)[>"]')
          if inc then includes[inc] = true end
        end
        f:close()
      end
    end
  end
  return includes
end

local function map_include_to_library(inc)
  local map = {
    ["SDL3/SDL.h"] = {"sdl3"}, ["SDL2/SDL.h"] = {"sdl2"}, ["SDL.h"] = {"sdl3", "sdl2"},
    ["SDL3_image/SDL_image.h"] = {"sdl3-image"}, ["SDL_image.h"] = {"sdl3-image", "sdl2-image"},
    ["SDL2/SDL_image.h"] = {"SDL2_image"}, ["SDL3_ttf/SDL_ttf.h"] = {"SDL3_ttf"},
    ["SDL3/SDL_ttf.h"] = {"SDL3_ttf"}, ["SDL_ttf.h"] = {"SDL3_ttf", "SDL2_ttf"},
    ["SDL2/SDL_ttf.h"] = {"SDL2_ttf"}, ["SDL3_mixer/SDL_mixer.h"] = {"SDL3_mixer"},
    ["SDL3/SDL_mixer.h"] = {"SDL3_mixer"}, ["SDL_mixer.h"] = {"SDL3_mixer", "SDL2_mixer"},
    ["SDL2/SDL_mixer.h"] = {"SDL2_mixer"}, ["SDL3_net/SDL_net.h"] = {"SDL3_net"},
    ["SDL3/SDL_net.h"] = {"SDL3_net"}, ["SDL_net.h"] = {"SDL3_net", "SDL2_net"},
    ["SDL2/SDL_net.h"] = {"SDL2_net"}, ["SDL3/SDL_opengl.h"] = {"sdl3"},
    ["SDL2/SDL_opengl.h"] = {"sdl2"}, ["GLFW/glfw3.h"] = {"glfw3"}, ["GL/glew.h"] = {"glew"},
    ["GL/gl.h"] = {"gl"}, ["GL/glu.h"] = {"glu"}, ["GL/glut.h"] = {"freeglut", "glut"},
    ["GL/freeglut.h"] = {"freeglut"}, ["GLUT/glut.h"] = {"freeglut", "glut"},
    ["vulkan/vulkan.h"] = {"vulkan"}, ["vulkan/vulkan.hpp"] = {"vulkan"},
    ["glad/glad.h"] = {"glad"}, ["glad/gl.h"] = {"glad"}, ["gtk/gtk.h"] = {"gtk4", "gtk+-3.0"},
    ["gtk-4.0/gtk/gtk.h"] = {"gtk4"}, ["gtk-3.0/gtk/gtk.h"] = {"gtk+-3.0"},
    ["qt5/QtCore/QCoreApplication"] = {"Qt5Core"}, ["qt6/QtCore/QCoreApplication"] = {"Qt6Core"},
    ["QCoreApplication"] = {"Qt6Core", "Qt5Core"}, ["AL/al.h"] = {"openal"}, ["AL/alc.h"] = {"openal"},
    ["portaudio.h"] = {"portaudio-2.0"}, ["pulse/pulseaudio.h"] = {"libpulse"},
    ["sndfile.h"] = {"sndfile"}, ["SFML/Audio.hpp"] = {"sfml-audio"}, ["FMOD/fmod.h"] = {},
    ["Eigen/Dense"] = {"eigen3"}, ["eigen3/Eigen/Dense"] = {"eigen3"}, ["glm/glm.hpp"] = {"glm"},
    ["bullet/btBulletDynamicsCommon.h"] = {"bullet"}, ["Box2D/Box2D.h"] = {"box2d"},
    ["curl/curl.h"] = {"libcurl"}, ["zmq.h"] = {"libzmq"}, ["asio.hpp"] = {"asio"},
    ["boost/asio.hpp"] = {"boost"}, ["ft2build.h"] = {"freetype2"},
    ["freetype2/ft2build.h"] = {"freetype2"}, ["png.h"] = {"libpng"}, ["jpeglib.h"] = {"libjpeg"},
    ["webp/decode.h"] = {"libwebp"}, ["zlib.h"] = {"zlib"}, ["opencv2/opencv.hpp"] = {"opencv4", "opencv"},
    ["opencv4/opencv2/opencv.hpp"] = {"opencv4"}, ["SFML/Graphics.hpp"] = {"sfml-graphics", "sfml-window", "sfml-system"},
    ["SFML/Window.hpp"] = {"sfml-window", "sfml-system"}, ["SFML/System.hpp"] = {"sfml-system"},
    ["raylib.h"] = {"raylib"}, ["json.hpp"] = {}, ["yaml-cpp/yaml.h"] = {"yaml-cpp"},
    ["pugixml.hpp"] = {"pugixml"}, ["sqlite3.h"] = {"sqlite3"}, ["postgresql/libpq-fe.h"] = {"libpq"},
    ["mysql/mysql.h"] = {"mysqlclient"}, ["tbb/tbb.h"] = {"tbb"}, ["omp.h"] = {}
  }
  return map[inc] or {}
end

local function get_library_priority()
  return {sdl3=100, sdl2=50, SDL3_image=100, SDL2_image=50, SDL3_ttf=100, SDL2_ttf=50,
    SDL3_mixer=100, SDL2_mixer=50, SDL3_net=100, SDL2_net=50, gtk4=100, ["gtk+-3.0"]=50,
    Qt6Core=100, Qt5Core=50, freeglut=100, glut=50, opencv4=100, opencv=50}
end

local function autodetect_libraries(files)
  local includes = scan_includes(files)
  local libs, seen = {}, {}
  for inc, _ in pairs(includes) do
    for _, lib in ipairs(map_include_to_library(inc)) do
      if lib ~= "" and not seen[lib] then seen[lib] = true table.insert(libs, lib) end
    end
  end
  if #libs == 0 then return "" end

  local priorities = get_library_priority()
  local families = {}
  for _, lib in ipairs(libs) do
    local fam = lib:match("^sdl3%-image") or lib:match("^sdl2%-image") and "sdl_image"
      or lib:match("^sdl3%-ttf") or lib:match("^sdl2%-ttf") and "sdl_ttf"
      or lib:match("^sdl3%-mixer") or lib:match("^sdl2%-mixer") and "sdl_mixer"
      or lib:match("^sdl3") or lib:match("^sdl2") and "sdl_core"
      or lib:match("^SDL%d+_") and lib:match("^(SDL%d+_[%a]+)")
      or lib:match("^Qt%d+") and "Qt"
      or lib:match("^gtk") and "gtk"
      or lib:match("^opencv") and "opencv"
      or lib:match("^([%a_%-]+)")
    families[fam] = families[fam] or {}
    table.insert(families[fam], lib)
  end

  local filtered = {}
  for _, flibs in pairs(families) do
    if #flibs == 1 then
      table.insert(filtered, flibs[1])
    else
      table.sort(flibs, function(a, b) return (priorities[a] or 0) > (priorities[b] or 0) end)
      for _, lib in ipairs(flibs) do
        if check_pkg_config(lib) then table.insert(filtered, lib) break end
      end
    end
  end

  local detected, flags_list = {}, {}
  for _, lib in ipairs(filtered) do
    if check_pkg_config(lib) then
      local flags = get_pkg_config_flags(lib)
      if flags then table.insert(detected, lib) table.insert(flags_list, flags) end
    end
  end

  local special = {}
  if includes["omp.h"] then table.insert(special, "-fopenmp") table.insert(detected, "OpenMP") end
  if #detected > 0 then vim.notify("Auto-detected: " .. table.concat(detected, ", "), vim.log.levels.INFO) end

  local all = table.concat(flags_list, " ")
  return #special > 0 and all .. " " .. table.concat(special, " ") or all
end

local function get_manual_opengl_flags(files)
  local includes = scan_includes(files)
  for inc, _ in pairs(includes) do
    if inc:match("^GL/") or inc:match("OpenGL") or inc:match("^GLFW/") or inc:match("glfw") or inc:match("SDL_opengl") then
      local sys = vim.loop.os_uname().sysname
      if sys == "Linux" then return "-lGL -lGLU"
      elseif sys == "Darwin" then return "-framework OpenGL -framework Cocoa -framework IOKit -framework CoreVideo"
      elseif sys:match("Windows") or sys:match("MINGW") or sys:match("MSYS") then return "-lopengl32 -lglu32" end
      return ""
    end
  end
  return ""
end

local function detect_shader_stage(path)
  local ext_map = {vert="vertex", vs="vertex", frag="fragment", fs="fragment", comp="compute",
    cs="compute", geom="geometry", gs="geometry", tesc="tesscontrol", tese="tesseval",
    hlsl="auto", fx="auto", metal="metal", spvasm="spirv-asm", glsl="auto"}
  local ext = path:match("%.([^.]+)$")
  local stage = ext and ext_map[ext]
  if stage and stage ~= "auto" then return stage end

  local f = io.open(path, "r")
  if not f then
    local fn = path:match("([^/\\]+)$")
    if fn then
      fn = fn:lower()
      if fn:match("vertex") or fn:match("vert") then return "vertex"
      elseif fn:match("fragment") or fn:match("frag") or fn:match("pixel") then return "fragment"
      elseif fn:match("compute") then return "compute"
      elseif fn:match("geometry") or fn:match("geom") then return "geometry"
      elseif fn:match("tess") then
        return fn:match("control") or fn:match("tesc") and "tesscontrol" or "tesseval"
      end
    end
    return "vertex"
  end

  local content = f:read("*a") f:close()
  if not content or content == "" then return "vertex" end

  if content:match("main%s*%(%)%s*{") or content:match("void%s+main%s*%(") then
    if content:match("gl_Position") or content:match("gl_VertexI") then return "vertex"
    elseif content:match("gl_Frag") or content:match("gl_FrontFacing") or content:match("gl_SampleID") then return "fragment"
    elseif content:match("gl_GlobalInvocationID") or content:match("gl_LocalInvocationID") or content:match("layout%s*%(local_size") then return "compute"
    elseif content:match("gl_PrimitiveIDIn") or content:match("EmitVertex") or content:match("EndPrimitive") then return "geometry"
    elseif content:match("gl_TessLevel") then
      return content:match("gl_InvocationID") and "tesscontrol" or "tesseval"
    end
    if content:match("layout%s*%([^%)]*location[^%)]*%)%s+in%s+vec") and not content:match("layout%s*%([^%)]*location[^%)]*%)%s+out%s+vec4") then
      return "vertex"
    elseif content:match("layout%s*%([^%)]*location[^%)]*%)%s+out%s+vec4") then return "fragment" end
  end
  return "vertex"
end

local function find_shader_files()
  local cwd, shaders = vim.fn.getcwd(), {}
  local exts = {"vert", "vs", "vsh", "v.glsl", "vert.glsl", "frag", "fs", "fsh", "f.glsl",
    "frag.glsl", "comp", "cs", "csh", "c.glsl", "comp.glsl", "geom", "gs", "gsh", "g.glsl",
    "geom.glsl", "tesc", "tcs", "tesc.glsl", "tese", "tes", "tese.glsl", "glsl", "hlsl",
    "fx", "fxh", "metal", "spvasm"}

  for _, ext in ipairs(exts) do
    local found = vim.fn.glob(cwd .. "/**/*." .. ext, false, true)
    if found and type(found) == "table" then
      for _, file in ipairs(found) do
        local stage = detect_shader_stage(file)
        shaders[stage] = shaders[stage] or {}
        table.insert(shaders[stage], file)
      end
    end
  end
  return shaders
end

local function generate_shader_commands()
  local shaders, cmds = find_shader_files(), {}
  local has = {glslc = vim.fn.executable("glslc") == 1, glslang = vim.fn.executable("glslangValidator") == 1,
    dxc = vim.fn.executable("dxc") == 1}
  if not (has.glslc or has.glslang or has.dxc) then
    vim.notify("No shader compiler found (glslc, glslangValidator, or dxc)", vim.log.levels.WARN)
    return {}
  end

  for stage, files in pairs(shaders) do
    for _, shader in ipairs(files) do
      local ext = shader:match("%.([^.]+)$")
      local out = shader:gsub("%.%w+$", ".spv")
      local cmd
      if ext == "hlsl" or ext == "fx" then
        if has.dxc then
          local prof = ({vertex="vs_6_0", fragment="ps_6_0", compute="cs_6_0", geometry="gs_6_0",
            tesscontrol="hs_6_0", tesseval="ds_6_0"})[stage] or "vs_6_0"
          cmd = "dxc -T " .. prof .. " -E main -Fo \"" .. out .. "\" \"" .. shader .. "\""
        end
      elseif ext == "metal" then
        out = shader:gsub("%.metal$", ".air")
        cmd = "xcrun -sdk macosx metal -c \"" .. shader .. "\" -o \"" .. out .. "\""
      else
        if has.glslc then
          cmd = "glslc --target-env=vulkan1.4 -fshader-stage=" .. stage .. " \"" .. shader .. "\" -o \"" .. out .. "\""
        elseif has.glslang then
          local sf = ({vertex="vert", fragment="frag", compute="comp", geometry="geom",
            tesscontrol="tesc", tesseval="tese"})[stage] or "vert"
          cmd = "glslangValidator --target-env vulkan1.4 -V -S " .. sf .. " \"" .. shader .. "\" -o \"" .. out .. "\""
        end
      end
      if cmd then table.insert(cmds, {input=shader, output=out, stage=stage, cmd=cmd}) end
    end
  end
  return cmds
end

local function generate_compile_commands(entry, files, args)
  local cwd, cmds, list = vim.fn.getcwd(), {}, {}
  for file in files:gmatch("[^%s]+") do
    file = file:gsub('"', '')
    local abs = file:match("^/") or file:match("^%a:") and file or cwd .. "/" .. file
    table.insert(cmds, {directory=cwd, command="g++ " .. args .. " -c " .. file, file=abs})
  end
  vim.fn.writefile({vim.fn.json_encode(cmds)}, cwd .. "/compile_commands.json")
  return cwd .. "/compile_commands.json"
end

M.options = {
  {text="Build and run program", value="option1"}, {text="Build program", value="option2"},
  {text="Run program", value="option3"}, {text="Compile shaders", value="option6"},
  {text="Build solution", value="option4"}, {text="", value="separator"},
  {text="Generate Compile Commands", value="option5"}
}

function M.action(opt)
  local utils = require("compiler.utils")
  local overseer = require("overseer")
  local entry = utils.os_path(vim.fn.getcwd() .. "/main.cpp")
  local files = utils.find_files_to_compile(entry, "*.cpp", true)
  local out_dir = utils.os_path(vim.fn.getcwd() .. "/bin/")
  local out = utils.os_path(vim.fn.getcwd() .. "/bin/program")
  local detected = autodetect_libraries(files)
  local manual = get_manual_opengl_flags(files)
  if manual ~= "" then detected = detected ~= "" and detected .. " " .. manual or manual end
  local args = "-Wall -Wextra -g -std=c++17 " .. detected
  local msg = "--task finished--"

  if opt == "option1" then
    overseer.new_task({name="- C++ compiler", strategy={"orchestrator", tasks={{
      name="- Build & run program → \"" .. entry .. "\"",
      cmd="rm -f \"" .. out .. "\" || true && mkdir -p \"" .. out_dir .. "\" && g++ " .. files .. " -o \"" .. out .. "\" " .. args .. " && \"" .. out .. "\" && echo \"\n" .. entry .. "\" && echo \"" .. msg .. "\"",
      components={"default_extended"},
      on_complete=function(t, c) vim.notify(c == 0 and "Build & run successful" or "Build & run failed", c == 0 and vim.log.levels.INFO or vim.log.levels.ERROR) end
    }}}}):start()
  elseif opt == "option2" then
    overseer.new_task({name="- C++ compiler", strategy={"orchestrator", tasks={{
      name="- Build program → \"" .. entry .. "\"",
      cmd="rm -f \"" .. out .. "\" || true && mkdir -p \"" .. out_dir .. "\" && g++ " .. files .. " -o \"" .. out .. "\" " .. args .. " && echo \"\n" .. entry .. "\" && echo \"" .. msg .. "\"",
      components={"default_extended"},
      on_complete=function(t, c) vim.notify(c == 0 and "Build successful" or "Build failed", c == 0 and vim.log.levels.INFO or vim.log.levels.ERROR) end
    }}}}):start()
  elseif opt == "option3" then
    overseer.new_task({name="- C++ compiler", strategy={"orchestrator", tasks={{
      name="- Run program → \"" .. out .. "\"",
      cmd="\"" .. out .. "\" && echo \"" .. out .. "\" && echo \"" .. msg .. "\"",
      components={"default_extended"}
    }}}}):start()
  elseif opt == "option4" then
    local sol = utils.get_solution_file()
    local tasks, execs = {}, {}
    if sol then
      local cfg = utils.parse_solution_file(sol)
      for e, v in pairs(cfg) do
        if e ~= "executables" then
          local ep = utils.os_path(v.entry_point)
          local fs = utils.find_files_to_compile(ep, "*.cpp")
          local o = utils.os_path(v.output)
          local od = utils.os_path(o:match("^(.-[/\\])[^/\\]*$"))
          local a = v.arguments or args
          table.insert(tasks, {name="- Build program → \"" .. ep .. "\"",
            cmd="rm -f \"" .. o .. "\" || true && mkdir -p \"" .. od .. "\" && g++ " .. fs .. " -o \"" .. o .. "\" " .. a .. " && echo \"\n" .. ep .. "\" && echo \"" .. msg .. "\"",
            components={"default_extended"}})
        end
      end
      if cfg.executables then
        for _, ex in pairs(cfg.executables) do
          ex = utils.os_path(ex, true)
          table.insert(execs, {name="- Run program → " .. ex, cmd=ex .. " && echo \"" .. ex .. "\" && echo \"" .. msg .. "\"", components={"default_extended"}})
        end
      end
      overseer.new_task({name="- C++ compiler", strategy={"orchestrator", tasks={tasks, execs}}}):start()
    else
      for _, ep in ipairs(utils.find_files(vim.fn.getcwd(), "main.cpp")) do
        ep = utils.os_path(ep)
        local fs = utils.find_files_to_compile(ep, "*.cpp")
        local od = utils.os_path(ep:match("^(.-[/\\])[^/\\]*$") .. "bin")
        local o = utils.os_path(od .. "/program")
        table.insert(tasks, {name="- Build program → \"" .. ep .. "\"",
          cmd="rm -f \"" .. o .. "\" || true && mkdir -p \"" .. od .. "\" && g++ " .. fs .. " -o \"" .. o .. "\" " .. args .. " && echo \"" .. ep .. "\" && echo \"" .. msg .. "\"",
          components={"default_extended"}})
      end
      overseer.new_task({name="- C++ compiler", strategy={"orchestrator", tasks=tasks}}):start()
    end
  elseif opt == "option5" then
    local outf = generate_compile_commands(entry, files, args)
    overseer.new_task({name="- Generate compile_commands.json", strategy={"orchestrator", tasks={{
      name="- Generate compile_commands.json → \"" .. outf .. "\"",
      cmd="echo 'Generated: " .. outf .. "' && echo \"" .. msg .. "\"",
      components={"default_extended"}
    }}}}):start()
  elseif opt == "option6" then
    local scmds = generate_shader_commands()
    if #scmds == 0 then vim.notify("No shader files found in project", vim.log.levels.WARN) return end
    local tasks, sfiles = {}, {}
    for _, si in ipairs(scmds) do
      local stat = vim.loop.fs_stat(si.input)
      if stat and stat.type ~= "directory" then
        table.insert(tasks, {name="- Compile shader → \"" .. si.input .. "\"", cmd=si.cmd .. " 2>&1",
          components={{"on_output_quickfix", open=false}, "default"}})
        table.insert(sfiles, si.input)
      end
    end
    if #tasks == 0 then vim.notify("No valid shader files to compile", vim.log.levels.WARN) return end
    overseer.new_task({name="- Shader compiler", strategy={"orchestrator", tasks=tasks},
      on_complete=function(t, c)
        if c == 0 then vim.notify("Successfully compiled " .. #tasks .. " shader(s)", vim.log.levels.INFO)
        else
          local failed = {}
          for _, sf in ipairs(sfiles) do
            if not vim.loop.fs_stat(sf:gsub("%.%w+$", ".spv")) then table.insert(failed, sf) end
          end
          vim.notify(#failed > 0 and "Shader compilation failed for: " .. table.concat(failed, ", ") or "Shader compilation failed", vim.log.levels.ERROR)
        end
      end}):start()
  end
end

return M
