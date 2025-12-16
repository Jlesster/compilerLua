--- C++ language actions with enhanced autodetection

local M = {}

-- Cache for pkg-config checks to avoid repeated system calls
local pkg_cache = {}

-- Helper: detect and get flags for a library using pkg-config (cached)
local function get_pkg_config_flags(lib_name)
  if pkg_cache[lib_name] ~= nil then
    return pkg_cache[lib_name]
  end

  local handle = io.popen("pkg-config --cflags --libs " .. lib_name .. " 2>/dev/null")
  if not handle then
    pkg_cache[lib_name] = false
    return nil
  end
  local flags = handle:read("*a")
  handle:close()

  if flags and flags ~= "" then
    flags = flags:gsub("\n", "")
    pkg_cache[lib_name] = flags
    return flags
  end
  pkg_cache[lib_name] = false
  return nil
end

-- Helper: check if a library exists via pkg-config (cached)
local function check_pkg_config(lib_name)
  if pkg_cache[lib_name] ~= nil then
    return pkg_cache[lib_name] ~= false
  end

  local handle = io.popen("pkg-config --exists " .. lib_name .. " 2>/dev/null && echo 'yes'")
  if not handle then
    pkg_cache[lib_name] = false
    return false
  end
  local result = handle:read("*a")
  handle:close()
  local exists = result:match("yes") ~= nil
  if not exists then
    pkg_cache[lib_name] = false
  end
  return exists
end

-- Helper: scan source files for #include directives (optimized)
local function scan_includes(files)
  local includes = {}
  local file_set = {}

  -- Parse file list
  local file_list = {}
  for file in files:gmatch("[^%s]+") do
    local clean_file = file:gsub('"', '')
    if not file_set[clean_file] then
      file_set[clean_file] = true
      table.insert(file_list, clean_file)
    end
  end

  -- Scan each file for includes
  for _, file in ipairs(file_list) do
    local f = io.open(file, "r")
    if f then
      for line in f:lines() do
        -- Match #include <library> or #include "library"
        local include = line:match('#include%s*[<"]([^>"]+)[>"]')
        if include then
          includes[include] = true
        end
      end
      f:close()
    end
  end

  return includes
end

-- Helper: comprehensive include to library mapping
local function map_include_to_library(include)
  local mapping = {
    -- SDL libraries (prefer SDL3 > SDL2)
    ["SDL3/SDL.h"] = {"sdl3"},
    ["SDL2/SDL.h"] = {"sdl2"},
    ["SDL.h"] = {"sdl3", "sdl2"},

    -- SDL3 Image library (multiple possible patterns)
    ["SDL3_image/SDL_image.h"] = {"sdl3-image"},
    ["SDL_image.h"] = {"sdl3-image", "sdl2-image"},

    -- SDL2 Image library
    ["SDL2/SDL_image.h"] = {"SDL2_image"},

    -- SDL3 TTF library
    ["SDL3_ttf/SDL_ttf.h"] = {"SDL3_ttf"},
    ["SDL3/SDL_ttf.h"] = {"SDL3_ttf"},
    ["SDL_ttf.h"] = {"SDL3_ttf", "SDL2_ttf"},

    -- SDL2 TTF library
    ["SDL2/SDL_ttf.h"] = {"SDL2_ttf"},

    -- SDL3 Mixer library
    ["SDL3_mixer/SDL_mixer.h"] = {"SDL3_mixer"},
    ["SDL3/SDL_mixer.h"] = {"SDL3_mixer"},
    ["SDL_mixer.h"] = {"SDL3_mixer", "SDL2_mixer"},

    -- SDL2 Mixer library
    ["SDL2/SDL_mixer.h"] = {"SDL2_mixer"},

    -- SDL3 Net library
    ["SDL3_net/SDL_net.h"] = {"SDL3_net"},
    ["SDL3/SDL_net.h"] = {"SDL3_net"},
    ["SDL_net.h"] = {"SDL3_net", "SDL2_net"},

    -- SDL2 Net library
    ["SDL2/SDL_net.h"] = {"SDL2_net"},

    -- SDL OpenGL integration (requires OpenGL linking)
    ["SDL3/SDL_opengl.h"] = {"sdl3"},
    ["SDL2/SDL_opengl.h"] = {"sdl2"},

    -- OpenGL/Graphics (prefer modern alternatives)
    ["GLFW/glfw3.h"] = {"glfw3"},
    ["GL/glew.h"] = {"glew"},
    ["GL/gl.h"] = {"gl"},
    ["GL/glu.h"] = {"glu"},
    ["GL/glut.h"] = {"freeglut", "glut"},
    ["GL/freeglut.h"] = {"freeglut"},
    ["GLUT/glut.h"] = {"freeglut", "glut"},
    ["vulkan/vulkan.h"] = {"vulkan"},
    ["vulkan/vulkan.hpp"] = {"vulkan"},

    -- GLFW alternatives
    ["glad/glad.h"] = {"glad"},
    ["glad/gl.h"] = {"glad"},

    -- UI Libraries (prefer GTK4 > GTK3)
    ["gtk/gtk.h"] = {"gtk4", "gtk+-3.0"},
    ["gtk-4.0/gtk/gtk.h"] = {"gtk4"},
    ["gtk-3.0/gtk/gtk.h"] = {"gtk+-3.0"},
    ["qt5/QtCore/QCoreApplication"] = {"Qt5Core"},
    ["qt6/QtCore/QCoreApplication"] = {"Qt6Core"},
    ["QCoreApplication"] = {"Qt6Core", "Qt5Core"},

    -- Audio
    ["AL/al.h"] = {"openal"},
    ["AL/alc.h"] = {"openal"},
    ["portaudio.h"] = {"portaudio-2.0"},
    ["pulse/pulseaudio.h"] = {"libpulse"},
    ["sndfile.h"] = {"sndfile"},
    ["SFML/Audio.hpp"] = {"sfml-audio"},
    ["FMOD/fmod.h"] = {},

    -- Math/Physics
    ["Eigen/Dense"] = {"eigen3"},
    ["eigen3/Eigen/Dense"] = {"eigen3"},
    ["glm/glm.hpp"] = {"glm"},
    ["bullet/btBulletDynamicsCommon.h"] = {"bullet"},
    ["Box2D/Box2D.h"] = {"box2d"},

    -- Networking
    ["curl/curl.h"] = {"libcurl"},
    ["zmq.h"] = {"libzmq"},
    ["asio.hpp"] = {"asio"},
    ["boost/asio.hpp"] = {"boost"},

    -- Image/Video
    ["ft2build.h"] = {"freetype2"},
    ["freetype2/ft2build.h"] = {"freetype2"},
    ["png.h"] = {"libpng"},
    ["jpeglib.h"] = {"libjpeg"},
    ["webp/decode.h"] = {"libwebp"},
    ["zlib.h"] = {"zlib"},
    ["opencv2/opencv.hpp"] = {"opencv4", "opencv"},
    ["opencv4/opencv2/opencv.hpp"] = {"opencv4"},

    -- Game engines/frameworks
    ["SFML/Graphics.hpp"] = {"sfml-graphics", "sfml-window", "sfml-system"},
    ["SFML/Window.hpp"] = {"sfml-window", "sfml-system"},
    ["SFML/System.hpp"] = {"sfml-system"},
    ["raylib.h"] = {"raylib"},

    -- Data formats
    ["json.hpp"] = {},
    ["yaml-cpp/yaml.h"] = {"yaml-cpp"},
    ["pugixml.hpp"] = {"pugixml"},
    ["sqlite3.h"] = {"sqlite3"},
    ["postgresql/libpq-fe.h"] = {"libpq"},
    ["mysql/mysql.h"] = {"mysqlclient"},

    -- Threading/Concurrency
    ["tbb/tbb.h"] = {"tbb"},
    ["omp.h"] = {},
  }

  return mapping[include] or {}
end

-- Helper: determine priority between library versions
local function get_library_priority()
  return {
    -- Graphics (prefer newer/better)
    ["sdl3"] = 100,
    ["sdl2"] = 50,
    ["SDL3_image"] = 100,
    ["SDL2_image"] = 50,
    ["SDL3_ttf"] = 100,
    ["SDL2_ttf"] = 50,
    ["SDL3_mixer"] = 100,
    ["SDL2_mixer"] = 50,
    ["SDL3_net"] = 100,
    ["SDL2_net"] = 50,

    -- UI (prefer GTK4 > GTK3, Qt6 > Qt5)
    ["gtk4"] = 100,
    ["gtk+-3.0"] = 50,
    ["Qt6Core"] = 100,
    ["Qt5Core"] = 50,

    -- OpenGL utilities (prefer freeglut > glut)
    ["freeglut"] = 100,
    ["glut"] = 50,

    -- Computer Vision
    ["opencv4"] = 100,
    ["opencv"] = 50,
  }
end

-- Helper: autodetect libraries based on actual includes
local function autodetect_libraries(files)
  -- Scan source files for includes
  local includes = scan_includes(files)

  -- Build list of required libraries based on includes
  local required_libs = {}
  local lib_set = {}

  for include, _ in pairs(includes) do
    local lib_candidates = map_include_to_library(include)
    for _, lib in ipairs(lib_candidates) do
      if lib ~= "" and not lib_set[lib] then
        lib_set[lib] = true
        table.insert(required_libs, lib)
      end
    end
  end

  -- If no libraries detected from includes, return empty
  if #required_libs == 0 then
    return ""
  end

  -- Get priority map
  local priorities = get_library_priority()

  -- Group libraries by family to handle version conflicts
  local lib_families = {}

  for _, lib in ipairs(required_libs) do
    -- Extract library family
    local family

    if lib:match("^sdl3%-image") or lib:match("^sdl2%-image") then
      family = "sdl_image"
    elseif lib:match("^sdl3%-ttf") or lib:match("^sdl2%-ttf") then
      family = "sdl_ttf"
    elseif lib:match("^sdl3%-mixer") or lib:match("^sdl2%-mixer") then
      family = "sdl_mixer"
    elseif lib:match("^sdl3") or lib:match("^sdl2") then
      family = "sdl_core"
    else
      family = lib:match("^([%a_%-]+)")
    end

    -- Handle special cases
    if lib:match("^SDL%d+_") then
      local base = lib:match("^(SDL%d+_[%a]+)")
      family = base or family
    elseif lib:match("^Qt%d+") then
      family = "Qt"
    elseif lib:match("^gtk") then
      family = "gtk"
    elseif lib:match("^opencv") then
      family = "opencv"
    end

    if not lib_families[family] then
      lib_families[family] = {lib}
    else
      table.insert(lib_families[family], lib)
    end
  end

  -- Keep only highest priority version of each library family
  local filtered_libs = {}
  for family, libs in pairs(lib_families) do
    if #libs == 1 then
      table.insert(filtered_libs, libs[1])
    else
      -- Sort by priority (highest first)
      table.sort(libs, function(a, b)
        return (priorities[a] or 0) > (priorities[b] or 0)
      end)
      -- Try libraries in priority order until one exists
      for _, lib in ipairs(libs) do
        if check_pkg_config(lib) then
          table.insert(filtered_libs, lib)
          break
        end
      end
    end
  end

  -- Check which libraries are actually available and get their flags
  local detected = {}
  local flags_list = {}

  for _, lib in ipairs(filtered_libs) do
    if check_pkg_config(lib) then
      local flags = get_pkg_config_flags(lib)
      if flags then
        table.insert(detected, lib)
        table.insert(flags_list, flags)
      end
    end
  end

  -- Add special compiler flags for certain includes
  local special_flags = {}
  if includes["omp.h"] then
    table.insert(special_flags, "-fopenmp")
    table.insert(detected, "OpenMP")
  end

  -- Notify user of detected libraries
  if #detected > 0 then
    vim.notify("Auto-detected: " .. table.concat(detected, ", "), vim.log.levels.INFO)
  end

  local all_flags = table.concat(flags_list, " ")
  if #special_flags > 0 then
    all_flags = all_flags .. " " .. table.concat(special_flags, " ")
  end

  return all_flags
end

-- Helper: get manual OpenGL flags for systems without pkg-config
local function get_manual_opengl_flags(files)
  -- Check if OpenGL is needed
  local includes = scan_includes(files)
  local needs_opengl = false

  for include, _ in pairs(includes) do
    if include:match("^GL/") or include:match("OpenGL") or
       include:match("^GLFW/") or include:match("glfw") or
       include:match("SDL_opengl") then
      needs_opengl = true
      break
    end
  end

  if not needs_opengl then
    return ""
  end

  local system = vim.loop.os_uname().sysname

  if system == "Linux" then
    return "-lGL -lGLU"
  elseif system == "Darwin" then
    return "-framework OpenGL -framework Cocoa -framework IOKit -framework CoreVideo"
  elseif system:match("Windows") or system:match("MINGW") or system:match("MSYS") then
    return "-lopengl32 -lglu32"
  end

  return ""
end

-- Helper: detect shader stage from file content and extension
local function detect_shader_stage(filepath)
  local ext = filepath:match("%.([^.]+)$")
  if not ext then
    return "vertex"
  end

  -- Extension-based detection (primary method)
  local ext_mappings = {
    -- GLSL extensions
    vert = "vertex",
    vs = "vertex",
    frag = "fragment",
    fs = "fragment",
    comp = "compute",
    cs = "compute",
    geom = "geometry",
    gs = "geometry",
    tesc = "tesscontrol",
    tese = "tesseval",

    -- HLSL extensions
    hlsl = "auto",
    fx = "auto",

    -- Metal extensions
    metal = "metal",

    -- SPIR-V assembly
    spvasm = "spirv-asm",

    -- Catch-all GLSL
    glsl = "auto"
  }

  local stage = ext_mappings[ext]

  -- If we have a definitive stage from extension, return it
  if stage and stage ~= "auto" then
    return stage
  end

  -- If extension indicates auto-detection needed, inspect content
  local f = io.open(filepath, "r")
  if not f then
    -- Can't open file, try filename pattern matching
    local filename = filepath:match("([^/\\]+)$")
    if filename then
      filename = filename:lower()
      if filename:match("vertex") or filename:match("vert") then
        return "vertex"
      elseif filename:match("fragment") or filename:match("frag") or filename:match("pixel") then
        return "fragment"
      elseif filename:match("compute") then
        return "compute"
      elseif filename:match("geometry") or filename:match("geom") then
        return "geometry"
      elseif filename:match("tess") then
        if filename:match("control") or filename:match("tesc") then
          return "tesscontrol"
        elseif filename:match("eval") or filename:match("tese") then
          return "tesseval"
        end
      end
    end
    return "vertex"
  end

  local content = f:read("*a")
  f:close()

  if not content or content == "" then
    return "vertex"
  end

  -- Check for shader stage indicators in content
  if content:match("main%s*%(%)%s*{") or content:match("void%s+main%s*%(") then
    -- Look for stage-specific keywords (more comprehensive detection)

    -- Vertex shader indicators
    if content:match("gl_Position") or
       content:match("gl_VertexID") or
       content:match("gl_VertexIndex") or
       content:match("gl_InstanceID") or
       content:match("gl_InstanceIndex") then
      return "vertex"

    -- Fragment shader indicators
    elseif content:match("gl_FragColor") or
           content:match("gl_FragCoord") or
           content:match("gl_FragDepth") or
           content:match("gl_FrontFacing") or
           content:match("gl_SampleID") or
           content:match("gl_SamplePosition") then
      return "fragment"

    -- Compute shader indicators
    elseif content:match("gl_GlobalInvocationID") or
           content:match("gl_LocalInvocationID") or
           content:match("gl_WorkGroupID") or
           content:match("gl_NumWorkGroups") or
           content:match("layout%s*%(local_size") then
      return "compute"

    -- Geometry shader indicators
    elseif content:match("gl_PrimitiveIDIn") or
           content:match("EmitVertex") or
           content:match("EndPrimitive") or
           content:match("gl_InvocationID.*geometry") then
      return "geometry"

    -- Tessellation control shader indicators
    elseif content:match("gl_TessLevelOuter") or
           content:match("gl_TessLevelInner") then
      if content:match("gl_InvocationID") then
        return "tesscontrol"
      else
        return "tesseval"
      end
    end

    -- Fallback: check layout qualifiers to distinguish vertex vs fragment
    -- Vertex shaders typically have "in" attributes, fragment shaders have "out" color
    if content:match("layout%s*%([^%)]*location[^%)]*%)%s+in%s+vec") and
       not content:match("layout%s*%([^%)]*location[^%)]*%)%s+out%s+vec4") then
      return "vertex"
    elseif content:match("layout%s*%([^%)]*location[^%)]*%)%s+out%s+vec4") then
      return "fragment"
    end
  end

  -- Check filename patterns as fallback
  local filename = filepath:match("([^/\\]+)$")
  if filename then
    filename = filename:lower()
    if filename:match("vertex") or filename:match("vert") then
      return "vertex"
    elseif filename:match("fragment") or filename:match("frag") or filename:match("pixel") then
      return "fragment"
    elseif filename:match("compute") then
      return "compute"
    elseif filename:match("geometry") or filename:match("geom") then
      return "geometry"
    elseif filename:match("tess") then
      if filename:match("control") or filename:match("tesc") then
        return "tesscontrol"
      elseif filename:match("eval") or filename:match("tese") then
        return "tesseval"
      end
    end
  end

  return "vertex"
end

-- Helper: find shader files in the project with comprehensive detection
local function find_shader_files()
  local cwd = vim.fn.getcwd()
  local shaders = {}

  -- Comprehensive list of shader file extensions
  local shader_extensions = {
    -- GLSL
    "vert", "vs", "vsh", "v.glsl", "vert.glsl",
    "frag", "fs", "fsh", "f.glsl", "frag.glsl",
    "comp", "cs", "csh", "c.glsl", "comp.glsl",
    "geom", "gs", "gsh", "g.glsl", "geom.glsl",
    "tesc", "tcs", "tesc.glsl",
    "tese", "tes", "tese.glsl",
    "glsl",

    -- HLSL
    "hlsl", "fx", "fxh",

    -- Metal
    "metal",

    -- SPIR-V assembly
    "spvasm",
  }

  -- Search for shader files
  for _, ext in ipairs(shader_extensions) do
    local pattern = cwd .. "/**/*." .. ext
    local found = vim.fn.glob(pattern, false, true)

    if found and type(found) == "table" then
      for _, file in ipairs(found) do
        -- Detect the shader stage
        local stage = detect_shader_stage(file)

        if not shaders[stage] then
          shaders[stage] = {}
        end

        table.insert(shaders[stage], file)
      end
    end
  end

  -- Also search for common naming patterns without specific extensions
  local patterns = {
    "*shader*",
    "*Shader*",
    "*.spv",
  }

  for _, pattern in ipairs(patterns) do
    local full_pattern = cwd .. "/**/" .. pattern
    local found = vim.fn.glob(full_pattern, false, true)

    if found and type(found) == "table" then
      for _, file in ipairs(found) do
        -- Skip if already processed or if it's a compiled output
        local already_added = false
        for _, stage_files in pairs(shaders) do
          for _, existing_file in ipairs(stage_files) do
            if existing_file == file then
              already_added = true
              break
            end
          end
          if already_added then break end
        end

        if not already_added and not file:match("%.spv$") then
          local stage = detect_shader_stage(file)
          if not shaders[stage] then
            shaders[stage] = {}
          end
          table.insert(shaders[stage], file)
        end
      end
    end
  end

  return shaders
end

-- Helper: generate shader compilation commands
local function generate_shader_commands()
  local shaders = find_shader_files()
  local commands = {}

  -- Check for available shader compilers
  local has_glslc = vim.fn.executable("glslc") == 1
  local has_glslangValidator = vim.fn.executable("glslangValidator") == 1
  local has_dxc = vim.fn.executable("dxc") == 1

  if not (has_glslc or has_glslangValidator or has_dxc) then
    vim.notify("No shader compiler found (glslc, glslangValidator, or dxc)", vim.log.levels.WARN)
    return {}
  end

  for stage, files in pairs(shaders) do
    for _, shader_file in ipairs(files) do
      local ext = shader_file:match("%.([^.]+)$")
      local output_file = shader_file:gsub("%.%w+$", ".spv")
      local cmd = nil

      -- Determine appropriate compiler and flags
      if ext == "hlsl" or ext == "fx" then
        -- Use DirectX Shader Compiler for HLSL
        if has_dxc then
          local profile_map = {
            vertex = "vs_6_0",
            fragment = "ps_6_0",
            compute = "cs_6_0",
            geometry = "gs_6_0",
            tesscontrol = "hs_6_0",
            tesseval = "ds_6_0",
          }
          local profile = profile_map[stage] or "vs_6_0"
          cmd = "dxc -T " .. profile .. " -E main -Fo \"" .. output_file .. "\" \"" .. shader_file .. "\""
        end
      elseif ext == "metal" then
        -- Metal shaders typically compile with xcrun metal
        output_file = shader_file:gsub("%.metal$", ".air")
        cmd = "xcrun -sdk macosx metal -c \"" .. shader_file .. "\" -o \"" .. output_file .. "\""
      else
        -- Use glslc or glslangValidator for GLSL with Vulkan 1.4 target
        if has_glslc then
          -- For .glsl files, auto-detect stage; for others, use detected stage
          if ext == "glsl" then
            cmd = "glslc --target-env=vulkan1.4 -fshader-stage=" .. stage ..
                  " \"" .. shader_file .. "\" -o \"" .. output_file .. "\""
          else
            cmd = "glslc --target-env=vulkan1.4 -fshader-stage=" .. stage ..
                  " \"" .. shader_file .. "\" -o \"" .. output_file .. "\""
          end
        elseif has_glslangValidator then
          local stage_flag_map = {
            vertex = "vert",
            fragment = "frag",
            compute = "comp",
            geometry = "geom",
            tesscontrol = "tesc",
            tesseval = "tese",
          }
          local stage_flag = stage_flag_map[stage] or "vert"
          cmd = "glslangValidator --target-env vulkan1.4 -V -S " .. stage_flag ..
                " \"" .. shader_file .. "\" -o \"" .. output_file .. "\""
        end
      end

      if cmd then
        table.insert(commands, {
          input = shader_file,
          output = output_file,
          stage = stage,
          cmd = cmd
        })
      end
    end
  end

  return commands
end

-- Helper: generate compile_commands.json
local function generate_compile_commands(entry_point, files, arguments)
  local cwd = vim.fn.getcwd()
  local commands = {}

  -- Split files string into individual files
  local file_list = {}
  for file in files:gmatch("[^%s]+") do
    local clean_file = file:gsub('"', '')
    file_list[#file_list + 1] = clean_file
  end

  -- Create a compilation database entry for each file
  for _, file in ipairs(file_list) do
    local abs_file = file
    if not file:match("^/") and not file:match("^%a:") then
      abs_file = cwd .. "/" .. file
    end

    commands[#commands + 1] = {
      directory = cwd,
      command = "g++ " .. arguments .. " -c " .. file,
      file = abs_file
    }
  end

  -- Write to compile_commands.json
  local json_content = vim.fn.json_encode(commands)
  local output_file = cwd .. "/compile_commands.json"
  vim.fn.writefile({json_content}, output_file)

  return output_file
end

--- Frontend - options displayed on telescope
M.options = {
  { text = "Build and run program", value = "option1" },
  { text = "Build program", value = "option2" },
  { text = "Run program", value = "option3" },
  { text = "Compile shaders", value = "option6" },
  { text = "Build solution", value = "option4" },
  { text = "", value = "separator" },
  { text = "Generate Compile Commands", value = "option5" }
}

--- Backend - overseer tasks performed on option selected
function M.action(selected_option)
  local utils = require("compiler.utils")
  local overseer = require("overseer")
  local entry_point = utils.os_path(vim.fn.getcwd() .. "/main.cpp")
  local files = utils.find_files_to_compile(entry_point, "*.cpp", true)
  local output_dir = utils.os_path(vim.fn.getcwd() .. "/bin/")
  local output = utils.os_path(vim.fn.getcwd() .. "/bin/program")

  -- Autodetect libraries based on actual includes in source files
  local detected_flags = autodetect_libraries(files)

  -- Always check for OpenGL needs and add manual flags if detected
  local manual_gl = get_manual_opengl_flags(files)
  if manual_gl ~= "" then
    if detected_flags ~= "" then
      detected_flags = detected_flags .. " " .. manual_gl
    else
      detected_flags = manual_gl
    end
  end

  local arguments = "-Wall -Wextra -g -std=c++17 " .. detected_flags
  local final_message = "--task finished--"


  if selected_option == "option1" then
    local task = overseer.new_task({
      name = "- C++ compiler",
      strategy = { "orchestrator",
        tasks = {{ name = "- Build & run program → \"" .. entry_point .. "\"",
          cmd = "rm -f \"" .. output .. "\" || true" ..
              " && mkdir -p \"" .. output_dir .. "\"" ..
              " && g++ " .. files .. " -o \"" .. output .. "\" " .. arguments ..
              " && \"" .. output .. "\"" ..
              " && echo \"\n" .. entry_point .. "\"" ..
              " && echo \"" .. final_message .. "\"",
          components = { "default_extended" },
          on_complete = function(task, code)
            if code == 0 then
              vim.notify("Build & run successful", vim.log.levels.INFO)
            else
              vim.notify("Build & run failed", vim.log.levels.ERROR)
            end
          end
        },},},})
    task:start()
  elseif selected_option == "option2" then
    local task = overseer.new_task({
      name = "- C++ compiler",
      strategy = { "orchestrator",
        tasks = {{ name = "- Build program → \"" .. entry_point .. "\"",
          cmd = "rm -f \"" .. output .. "\" || true" ..
              " && mkdir -p \"" .. output_dir .. "\"" ..
              " && g++ " .. files .. " -o \"" .. output .. "\" " .. arguments ..
              " && echo \"\n" .. entry_point .. "\"" ..
              " && echo \"" .. final_message .. "\"",
          components = { "default_extended" },
          on_complete = function(task, code)
            if code == 0 then
              vim.notify("Build successful", vim.log.levels.INFO)
            else
              vim.notify("Build failed", vim.log.levels.ERROR)
            end
          end
        },},},})
    task:start()
  elseif selected_option == "option3" then
    local task = overseer.new_task({
      name = "- C++ compiler",
      strategy = { "orchestrator",
        tasks = {{ name = "- Run program → \"" .. output .. "\"",
          cmd = "\"" .. output .. "\"" ..
              " && echo \"" .. output .. "\"" ..
              " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        },},},})
    task:start()
  elseif selected_option == "option4" then
    local entry_points
    local task = {}
    local tasks = {}
    local executables = {}

    -- if .solution file exists in working dir
    local solution_file = utils.get_solution_file()
    if solution_file then
      local config = utils.parse_solution_file(solution_file)

      for entry, variables in pairs(config) do
        if entry == "executables" then goto continue end
        entry_point = utils.os_path(variables.entry_point)
        files = utils.find_files_to_compile(entry_point, "*.cpp")
        output = utils.os_path(variables.output)
        output_dir = utils.os_path(output:match("^(.-[/\\])[^/\\]*$"))
        arguments = variables.arguments or arguments
        task = { name = "- Build program → \"" .. entry_point .. "\"",
          cmd = "rm -f \"" .. output .. "\" || true" ..
              " && mkdir -p \"" .. output_dir .. "\"" ..
              " && g++ " .. files .. " -o \"" .. output .. "\" " .. arguments ..
              " && echo \"\n" .. entry_point .. "\"" ..
              " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        }
        table.insert(tasks, task)
        ::continue::
      end

      local solution_executables = config["executables"]
      if solution_executables then
        for entry, executable in pairs(solution_executables) do
          executable = utils.os_path(executable, true)
          task = { name = "- Run program → " .. executable,
            cmd = executable ..
                  " && echo \"" .. executable .. "\"" ..
                  " && echo \"" .. final_message .. "\"",
            components = { "default_extended" }
          }
          table.insert(executables, task)
        end
      end

      task = overseer.new_task({
        name = "- C++ compiler", strategy = { "orchestrator",
          tasks = {
            tasks,
            executables
          }}})
      task:start()

    else
      entry_points = utils.find_files(vim.fn.getcwd(), "main.cpp")

      for _, entry_point in ipairs(entry_points) do
        entry_point = utils.os_path(entry_point)
        files = utils.find_files_to_compile(entry_point, "*.cpp")
        output_dir = utils.os_path(entry_point:match("^(.-[/\\])[^/\\]*$") .. "bin")
        output = utils.os_path(output_dir .. "/program")
        task = { name = "- Build program → \"" .. entry_point .. "\"",
          cmd = "rm -f \"" .. output .. "\" || true" ..
              " && mkdir -p \"" .. output_dir .. "\"" ..
              " && g++ " .. files .. " -o \"" .. output .. "\" " .. arguments ..
              " && echo \"" .. entry_point .. "\"" ..
              " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        }
        table.insert(tasks, task)
      end

      task = overseer.new_task({
        name = "- C++ compiler", strategy = { "orchestrator", tasks = tasks }
      })
      task:start()
    end
  elseif selected_option == "option5" then
    local output_file = generate_compile_commands(entry_point, files, arguments)

    local task = overseer.new_task({
      name = "- Generate compile_commands.json",
      strategy = { "orchestrator",
        tasks = {{ name = "- Generate compile_commands.json → \"" .. output_file .. "\"",
          cmd = "echo 'Generated: " .. output_file .. "'" ..
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        },},},})
    task:start()
  elseif selected_option == "option6" then
    local shader_commands = generate_shader_commands()

    if #shader_commands == 0 then
      vim.notify("No shader files found in project", vim.log.levels.WARN)
      return
    end

    local tasks = {}
    local valid_count = 0
    local shader_files = {}

    for _, shader_info in ipairs(shader_commands) do
      local stat = vim.loop.fs_stat(shader_info.input)
      if stat and stat.type ~= "directory" then
        local task = {
          name = "- Compile shader → \"" .. shader_info.input .. "\"",
          cmd = shader_info.cmd .. " 2>&1",
          components = {
            { "on_output_quickfix", open = false },
            "default"
          }
        }
        table.insert(tasks, task)
        table.insert(shader_files, shader_info.input)
        valid_count = valid_count + 1
      end
    end

    if #tasks == 0 then
      vim.notify("No valid shader files to compile", vim.log.levels.WARN)
      return
    end

    local task = overseer.new_task({
      name = "- Shader compiler",
      strategy = { "orchestrator", tasks = tasks },
      on_complete = function(task, code)
        if code == 0 then
          vim.notify("Successfully compiled " .. valid_count .. " shader(s)", vim.log.levels.INFO)
        else
          -- Parse which shaders failed
          local failed_shaders = {}
          for i, shader_file in ipairs(shader_files) do
            local output_file = shader_file:gsub("%.%w+$", ".spv")
            local stat = vim.loop.fs_stat(output_file)
            if not stat then
              table.insert(failed_shaders, shader_file)
            end
          end

          if #failed_shaders > 0 then
            vim.notify("Shader compilation failed for: " .. table.concat(failed_shaders, ", "), vim.log.levels.ERROR)
          else
            vim.notify("Shader compilation failed", vim.log.levels.ERROR)
          end
        end
      end
    })
    task:start()
  end
end

return M
