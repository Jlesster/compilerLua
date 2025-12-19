--- Optimized Java language actions
local M = {}

local function read_pom()
  local pom = vim.fn.getcwd() .. "/pom.xml"
  return vim.fn.filereadable(pom) == 1 and table.concat(vim.fn.readfile(pom), "\n") or nil
end

local function get_main_class()
  local content = read_pom()
  if content then
    local match = content:match("<mainClass>(.-)</mainClass>")
    if match then return match end
  end

  local paths = vim.fn.isdirectory(vim.fn.getcwd() .. "/src/main/java") == 1
    and {vim.fn.getcwd() .. "/src/main/java"} or {vim.fn.getcwd()}

  for _, path in ipairs(paths) do
    for _, file in ipairs(vim.fn.globpath(path, "**/*.java", false, true)) do
      local pkg, cls, has_main
      for _, line in ipairs(vim.fn.readfile(file)) do
        pkg = pkg or line:match("^%s*package%s+([%w%.]+)")
        cls = cls or line:match("^%s*public%s+class%s+(%w+)")
        has_main = has_main or line:match("void%s+main%s*%(")
        if cls and has_main then return pkg and pkg .. "." .. cls or cls end
      end
    end
  end
  return "Main"
end

local function get_lwjgl_args()
  local content = read_pom()
  if not content or not content:match("lwjgl") then return "" end
  local os_name = vim.loop.os_uname().sysname
  local natives = os_name == "Darwin" and (vim.loop.os_uname().machine == "arm64" and "natives-macos-arm64" or "natives-macos")
    or (os_name:match("Windows") and "natives-windows" or "natives-linux")
  return " -Dorg.lwjgl.librarypath=target/natives-" .. natives .. (os_name == "Linux" and " -Dorg.lwjgl.glfw.libname=glfw" or "")
end

local function add_dependency_to_pom(dep_name, dep_config)
  local pom_path = vim.fn.getcwd() .. "/pom.xml"
  if vim.fn.filereadable(pom_path) == 0 then
    print("No pom.xml found"); return false
  end

  local lines = vim.fn.readfile(pom_path)
  for _, line in ipairs(lines) do
    if line:match(dep_config.artifactId) then
      print(dep_name .. " already configured"); return true
    end
  end

  local new_lines, state = {}, {props=false, dep_mgmt=false, deps=false, in_props=false, in_dep_mgmt=false,
    in_dep_mgmt_deps=false, in_deps=false, dep_mgmt_depth=0, deps_indent=""}

  for i, line in ipairs(lines) do
    table.insert(new_lines, line)

    -- Properties
    if dep_config.properties and not state.props then
      if line:match("<%s*properties%s*>") then state.in_props = true
      elseif state.in_props and line:match("<%s*/properties%s*>") then
        for _, prop in ipairs(dep_config.properties) do table.insert(new_lines, #new_lines, prop) end
        state.props = true
      end
    else state.props = true end

    -- Track dependencyManagement depth
    if line:match("<%s*dependencyManagement%s*>") then
      state.in_dep_mgmt, state.dep_mgmt_depth = true, state.dep_mgmt_depth + 1
    elseif line:match("<%s*/dependencyManagement%s*>") then
      state.dep_mgmt_depth = state.dep_mgmt_depth - 1
      if state.dep_mgmt_depth == 0 then state.in_dep_mgmt, state.in_dep_mgmt_deps = false, false end
    end

    -- DependencyManagement
    if dep_config.dependencyManagement and not state.dep_mgmt then
      if state.in_dep_mgmt and line:match("<%s*dependencies%s*>") then state.in_dep_mgmt_deps = true
      elseif state.in_dep_mgmt_deps and line:match("<%s*/dependencies%s*>") then
        for _, mgmt in ipairs(dep_config.dependencyManagement) do table.insert(new_lines, #new_lines, mgmt) end
        state.dep_mgmt = true
      end
    else state.dep_mgmt = true end

    -- Dependencies
    if not state.deps then
      if line:match("<%s*dependencies%s*>") and not state.in_dep_mgmt then
        state.in_deps, state.deps_indent = true, line:match("^(%s*)")
      elseif state.in_deps and line:match("<%s*/dependencies%s*>") then
        for _, dep in ipairs(dep_config.lines) do table.insert(new_lines, #new_lines, state.deps_indent .. dep) end
        state.deps, state.in_deps = true, false
      end
    end
  end

  -- Create dependencies section if missing
  if not state.deps then
    for i = #new_lines, 1, -1 do
      if new_lines[i]:match("<%s*/project%s*>") then
        local indent = new_lines[i]:match("^(%s*)")
        table.insert(new_lines, i, indent .. "</dependencies>")
        for j = #dep_config.lines, 1, -1 do table.insert(new_lines, i, indent .. "  " .. dep_config.lines[j]) end
        table.insert(new_lines, i, indent .. "<dependencies>")
        table.insert(new_lines, i, "")
        state.deps = true
        break
      end
    end
  end

  if state.props and state.dep_mgmt and state.deps then
    vim.fn.writefile(new_lines, pom_path)
    print(dep_name .. " added to pom.xml")
    return true
  end
  print("Failed - missing sections (props=" .. tostring(state.props) .. " dep_mgmt=" .. tostring(state.dep_mgmt) .. " deps=" .. tostring(state.deps) .. ")")
  return false
end

local function add_jackson_json()
  return add_dependency_to_pom("Jackson JSON", {
    artifactId = "jackson-databind",
    lines = {
      "  <!-- Jackson JSON Library -->",
      "  <dependency><groupId>com.fasterxml.jackson.core</groupId><artifactId>jackson-databind</artifactId><version>2.18.2</version></dependency>",
      "  <dependency><groupId>com.fasterxml.jackson.core</groupId><artifactId>jackson-core</artifactId><version>2.18.2</version></dependency>",
      "  <dependency><groupId>com.fasterxml.jackson.core</groupId><artifactId>jackson-annotations</artifactId><version>2.18.2</version></dependency>"
    }
  })
end

local function add_lwjgl_library()
  local pom_path = vim.fn.getcwd() .. "/pom.xml"
  if vim.fn.filereadable(pom_path) == 0 then print("No pom.xml found"); return false end
  local content = table.concat(vim.fn.readfile(pom_path), "\n")
  if content:match("lwjgl%-bom") or content:match("<artifactId>lwjgl</artifactId>") then
    print("LWJGL already configured"); return true
  end

  local success = add_dependency_to_pom("LWJGL", {
    artifactId = "lwjgl-bom",
    properties = {
      "  <lwjgl.version>3.3.6</lwjgl.version>", "  <joml.version>1.10.8</joml.version>",
      "  <joml-primitives.version>1.10.0</joml-primitives.version>", "  <lwjgl3-awt.version>0.1.8</lwjgl3-awt.version>",
      "  <steamworks4j.version>1.9.0</steamworks4j.version>", "  <steamworks4j-server.version>1.9.0</steamworks4j-server.version>",
      "  <lwjgl.natives>natives-linux</lwjgl.natives>"
    },
    dependencyManagement = {
      "  <dependency>", "    <groupId>org.lwjgl</groupId>", "    <artifactId>lwjgl-bom</artifactId>",
      "    <version>${lwjgl.version}</version>", "    <scope>import</scope>", "    <type>pom</type>", "  </dependency>"
    },
    lines = {
      "  <!-- LWJGL Core Modules -->",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-assimp</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-bgfx</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-cuda</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-egl</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-fmod</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-freetype</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-glfw</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-harfbuzz</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-hwloc</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-jawt</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-jemalloc</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-ktx</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-libdivide</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-llvm</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-lmdb</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-lz4</artifactId></dependency>",
      " <dependency><groupId>io.github.spair</groupId><artifactId>imgui-java-binding</artifactId><version>1.86.11</version></dependency>",
      " <dependency><groupId>io.github.spair</groupId><artifactId>imgui-java-lwjgl3</artifactId><version>1.86.11</version></dependency>",
      " <dependency><groupId>io.github.spair</groupId><artifactId>imgui-java-natives-linux</artifactId><version>1.86.11</version></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-meow</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-meshoptimizer</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-msdfgen</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-nanovg</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-nfd</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-nuklear</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-odbc</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-openal</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-opencl</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-opengl</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-opengles</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-openvr</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-openxr</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-opus</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-par</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-remotery</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-rpmalloc</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-shaderc</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-spvc</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-sse</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-stb</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-tinyexr</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-tinyfd</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-tootle</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-vma</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-vulkan</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-xxhash</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-yoga</artifactId></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-zstd</artifactId></dependency>",
      " ", "  <!-- LWJGL Native Libraries -->",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-assimp</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-bgfx</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-freetype</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-glfw</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-harfbuzz</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-hwloc</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-jemalloc</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-ktx</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-libdivide</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-llvm</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-lmdb</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-lz4</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-meow</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-meshoptimizer</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-msdfgen</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-nanovg</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-nfd</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-nuklear</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-openal</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-opengl</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-opengles</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-openvr</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-openxr</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-opus</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-par</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-remotery</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-rpmalloc</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-shaderc</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-spvc</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-sse</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-stb</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-tinyexr</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-tinyfd</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-tootle</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-vma</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-xxhash</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-yoga</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-zstd</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
      " ", "  <!-- Additional Libraries -->",
      " <dependency><groupId>org.joml</groupId><artifactId>joml</artifactId><version>${joml.version}</version></dependency>",
      " <dependency><groupId>org.joml</groupId><artifactId>joml-primitives</artifactId><version>${joml-primitives.version}</version></dependency>",
      " <dependency><groupId>org.lwjglx</groupId><artifactId>lwjgl3-awt</artifactId><version>${lwjgl3-awt.version}</version></dependency>",
      " <dependency><groupId>com.code-disaster.steamworks4j</groupId><artifactId>steamworks4j</artifactId><version>${steamworks4j.version}</version></dependency>",
      " <dependency><groupId>com.code-disaster.steamworks4j</groupId><artifactId>steamworks4j-server</artifactId><version>${steamworks4j-server.version}</version></dependency>"
    }
  })
  if success then print("Note: Change <lwjgl.natives> property if not on Linux") end
  return success
end

local function update_pom_for_fatjar()
  local pom_path = vim.fn.getcwd() .. "/pom.xml"
  if vim.fn.filereadable(pom_path) == 0 then print("No pom.xml found"); return false end

  local lines, main_class = vim.fn.readfile(pom_path), get_main_class()
  local in_pm, has_shade = false, false
  for i, line in ipairs(lines) do
    if line:match("<%s*pluginManagement%s*>") then in_pm = true
    elseif line:match("<%s*/pluginManagement%s*>") then in_pm = false
    elseif not in_pm and line:match("maven%-shade%-plugin") then has_shade = true; break end
  end
  if has_shade then print("Maven Shade Plugin already configured"); return true end

  local shade = {
    "      <plugin>", "        <groupId>org.apache.maven.plugins</groupId>",
    "        <artifactId>maven-shade-plugin</artifactId>", "        <version>3.5.1</version>",
    "        <executions>", "          <execution>", "            <phase>package</phase>",
    "            <goals>", "              <goal>shade</goal>", "            </goals>",
    "            <configuration>", "              <transformers>",
    "                <transformer implementation=\"org.apache.maven.plugins.shade.resource.ManifestResourceTransformer\">",
    "                  <mainClass>" .. main_class .. "</mainClass>", "                </transformer>",
    "              </transformers>", "              <filters>", "                <filter>",
    "                  <artifact>*:*</artifact>", "                  <excludes>",
    "                    <exclude>META-INF/*.SF</exclude>", "                    <exclude>META-INF/*.DSA</exclude>",
    "                    <exclude>META-INF/*.RSA</exclude>", "                  </excludes>",
    "                </filter>", "              </filters>",
    "              <finalName>${project.artifactId}-${project.version}-fat</finalName>",
    "            </configuration>", "          </execution>", "        </executions>", "      </plugin>"
  }

  local new_lines, inserted, state = {}, false, {in_pm=false, in_build=false, in_plugins=false, pm_depth=0, build_indent=""}
  for i, line in ipairs(lines) do
    if line:match("<%s*pluginManagement%s*>") then
      state.in_pm, state.pm_depth = true, state.pm_depth + 1
    elseif line:match("<%s*/pluginManagement%s*>") then
      state.pm_depth = state.pm_depth - 1
      if state.pm_depth == 0 then
        state.in_pm = false
        table.insert(new_lines, line)
        local has_plugins_after = false
        for j = i + 1, math.min(i + 5, #lines) do
          if lines[j]:match("<%s*plugins%s*>") and not lines[j]:match("<%s*pluginManagement") then has_plugins_after = true; break
          elseif lines[j]:match("<%s*/build%s*>") then break end
        end
        if not has_plugins_after and not inserted then
          table.insert(new_lines, state.build_indent .. "    <plugins>")
          for _, l in ipairs(shade) do table.insert(new_lines, l) end
          table.insert(new_lines, state.build_indent .. "    </plugins>")
          inserted = true
        end
        goto continue
      end
    end

    if not state.in_pm then
      if line:match("<%s*build%s*>") then state.in_build, state.build_indent = true, line:match("^(%s*)")
      elseif state.in_build and line:match("<%s*plugins%s*>") then state.in_plugins = true
      elseif state.in_plugins and line:match("<%s*/plugins%s*>") then
        for _, l in ipairs(shade) do table.insert(new_lines, l) end
        inserted = true
      end
    end
    table.insert(new_lines, line)
    ::continue::
  end

  if inserted then
    vim.fn.writefile(new_lines, pom_path)
    print("Maven Shade Plugin added for: " .. main_class)
    return true
  end
  print("Failed - couldn't find insertion point")
  return false
end

M.options = {
  {text=" Maven: Build & Run", value="mvn_run"}, {text=" Maven: Build", value="mvn_build"},
  {text=" Maven: Clean Build", value="mvn_clean"}, {text=" Maven: Test", value="mvn_test"},
  {text="", value="separator"},
  {text=" Maven: Package Fat Jar", value="mvn_pkg"},{text=" Maven: Run Fat Jar", value="mvn_jar"},
  {text=" Maven: Run with Dependencies", value="mvn_jar_cp"},
  {text=" Maven: Setup Fat Jar Build", value="mvn_setup"},
  {text="", value="separator"},
  {text=" Add: Jackson JSON Library", value="add_jackson"}, {text="Add: LWJGL Library", value="add_lwjgl"},
  {text="", value="separator"},
  {text="Quick Run", value="quick"}, {text="Build", value="build"}, {text="Run", value="run"},
}

function M.action(opt)
  local overseer, cwd, main_cls, lwjgl = require("overseer"), vim.fn.getcwd(), get_main_class(), get_lwjgl_args()
  local msg = " && echo '\\n--done--'"

  local function task(name, cmd)
    overseer.new_task({name="- "..name, strategy={"orchestrator", tasks={{name="- "..name, cmd=cmd..msg, components={"default_extended"}}}}}):start()
  end

  local cmds = {
    mvn_run = "mvn compile exec:java -Dexec.mainClass=" .. main_cls,
    mvn_build = "mvn compile", mvn_clean = "mvn clean compile", mvn_pkg = "mvn clean package",
    mvn_jar = "bash -c 'cd " .. cwd .. " && JAR=$(find target -type f \\( -name \"*-fat.jar\" -o -name \"*-jar-with-dependencies.jar\" \\) 2>/dev/null | head -n 1) && if [ -z \"$JAR\" ]; then echo \"No fat JAR found. Available JARs:\" && ls -la target/*.jar 2>/dev/null || echo \"No JARs in target/\"; exit 1; fi && echo \"Running: $JAR\" && java" .. lwjgl .. " -jar \"$JAR\"'",
    mvn_jar_cp = "bash -c 'cd " .. cwd .. " && java" .. lwjgl .. " -cp \"target/*:target/classes\" " .. main_cls .. "'",
    mvn_test = "mvn test", quick = "mvn -o compile exec:java -Dexec.mainClass=" .. main_cls,
    build = "mkdir -p bin && javac -d bin $(find . -name '*.java')",
    run = "java" .. lwjgl .. " -cp bin " .. main_cls:match("([^%.]+)$"),
  }

  if opt == "mvn_setup" then update_pom_for_fatjar()
  elseif opt == "add_jackson" then add_jackson_json()
  elseif opt == "add_lwjgl" then add_lwjgl_library()
  elseif cmds[opt] then task(opt:gsub("_", " "), cmds[opt]) end
end

return M
