--- Optimized Java language actions
local M = {}

local function read_pom()
  local pom = vim.fn.getcwd() .. "/pom.xml"
  if vim.fn.filereadable(pom) == 0 then return nil end
  return table.concat(vim.fn.readfile(pom), "\n")
end

local function get_main_class()
  local content = read_pom()
  if content then
    local match = content:match("<mainClass>(.-)</mainClass>")
    if match then return match end
  end

  -- Auto-detect from source files
  local paths = vim.fn.isdirectory(vim.fn.getcwd() .. "/src/main/java") == 1
    and {vim.fn.getcwd() .. "/src/main/java"}
    or {vim.fn.getcwd()}

  for _, path in ipairs(paths) do
    for _, file in ipairs(vim.fn.globpath(path, "**/*.java", false, true)) do
      local pkg, cls, has_main
      for _, line in ipairs(vim.fn.readfile(file)) do
        pkg = pkg or line:match("^%s*package%s+([%w%.]+)")
        cls = cls or line:match("^%s*public%s+class%s+(%w+)")
        has_main = has_main or line:match("void%s+main%s*%(")
        if cls and has_main then
          return pkg and pkg .. "." .. cls or cls
        end
      end
    end
  end
  return "Main"
end

local function get_lwjgl_args()
  local content = read_pom()
  if not content or not content:match("lwjgl") then return "" end

  local os_name = vim.loop.os_uname().sysname
  local natives = os_name == "Darwin" and
    (vim.loop.os_uname().machine == "arm64" and "natives-macos-arm64" or "natives-macos") or
    (os_name:match("Windows") and "natives-windows" or "natives-linux")

  local args = " -Dorg.lwjgl.librarypath=target/natives-" .. natives
  if os_name == "Linux" then
    args = args .. " -Dorg.lwjgl.glfw.libname=glfw"
  end
  return args
end

local function add_dependency_to_pom(dep_name, dep_config)
  local pom_path = vim.fn.getcwd() .. "/pom.xml"
  if vim.fn.filereadable(pom_path) == 0 then
    print("No pom.xml found in current directory")
    return false
  end

  local lines = vim.fn.readfile(pom_path)

  -- Check if dependency already exists
  for _, line in ipairs(lines) do
    if line:match(dep_config.artifactId) then
      print(dep_name .. " already configured in pom.xml")
      return true
    end
  end

  local new_lines = {}
  local inserted = false
  local in_dependencies = false
  local dependencies_indent = ""

  for i, line in ipairs(lines) do
    table.insert(new_lines, line)

    if not inserted then
      if line:match("<%s*dependencies%s*>") then
        in_dependencies = true
        dependencies_indent = line:match("^(%s*)")
      elseif in_dependencies and line:match("<%s*/dependencies%s*>") then
        -- Insert before </dependencies>
        for _, dep_line in ipairs(dep_config.lines) do
          table.insert(new_lines, #new_lines, dependencies_indent .. "  " .. dep_line)
        end
        inserted = true
      end
    end
  end

  if inserted then
    vim.fn.writefile(new_lines, pom_path)
    print(dep_name .. " added to pom.xml")
    return true
  else
    print("Failed to update pom.xml - couldn't find <dependencies> section")
    return false
  end
end

local function add_jackson_json()
  local jackson_config = {
    artifactId = "jackson-databind",
    lines = {
      "<!-- Jackson JSON Library -->",
      "<dependency>",
      "  <groupId>com.fasterxml.jackson.core</groupId>",
      "  <artifactId>jackson-databind</artifactId>",
      "  <version>2.18.2</version>",
      "</dependency>",
      "<dependency>",
      "  <groupId>com.fasterxml.jackson.core</groupId>",
      "  <artifactId>jackson-core</artifactId>",
      "  <version>2.18.2</version>",
      "</dependency>",
      "<dependency>",
      "  <groupId>com.fasterxml.jackson.core</groupId>",
      "  <artifactId>jackson-annotations</artifactId>",
      "  <version>2.18.2</version>",
      "</dependency>"
    }
  }
  return add_dependency_to_pom("Jackson JSON", jackson_config)
end

local function add_lwjgl_library()
  local pom_path = vim.fn.getcwd() .. "/pom.xml"
  if vim.fn.filereadable(pom_path) == 0 then
    print("No pom.xml found in current directory")
    return false
  end

  local content = table.concat(vim.fn.readfile(pom_path), "\n")

  -- Check if LWJGL already exists
  if content:match("lwjgl") then
    print("LWJGL already configured in pom.xml")
    return true
  end

  local lines = vim.fn.readfile(pom_path)
  local new_lines = {}
  local inserted_props = false
  local inserted_dep_mgmt = false
  local inserted_deps = false

  -- LWJGL properties
  local lwjgl_props = {
    "    <lwjgl.version>3.3.6</lwjgl.version>",
    "    <joml.version>1.10.8</joml.version>",
    "    <lwjgl.natives>natives-linux</lwjgl.natives>"
  }

  -- LWJGL dependency management
  local lwjgl_dep_mgmt = {
    "    <dependency>",
    "      <groupId>org.lwjgl</groupId>",
    "      <artifactId>lwjgl-bom</artifactId>",
    "      <version>${lwjgl.version}</version>",
    "      <scope>import</scope>",
    "      <type>pom</type>",
    "    </dependency>"
  }

  -- Core LWJGL dependencies
  local lwjgl_deps = {
    "    <!-- LWJGL Core -->",
    "    <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl</artifactId></dependency>",
    "    <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-glfw</artifactId></dependency>",
    "    <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-opengl</artifactId></dependency>",
    "    <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-stb</artifactId></dependency>",
    "    ",
    "    <!-- LWJGL Natives -->",
    "    <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
    "    <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-glfw</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
    "    <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-opengl</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
    "    <dependency><groupId>org.lwjgl</groupId><artifactId>lwjgl-stb</artifactId><classifier>${lwjgl.natives}</classifier></dependency>",
    "    ",
    "    <!-- JOML Math Library -->",
    "    <dependency><groupId>org.joml</groupId><artifactId>joml</artifactId><version>${joml.version}</version></dependency>"
  }

  local in_properties = false
  local in_dep_mgmt = false
  local in_dep_mgmt_deps = false
  local in_dependencies = false

  for i, line in ipairs(lines) do
    table.insert(new_lines, line)

    -- Add to properties
    if not inserted_props then
      if line:match("<%s*properties%s*>") then
        in_properties = true
      elseif in_properties and line:match("<%s*/properties%s*>") then
        for _, prop_line in ipairs(lwjgl_props) do
          table.insert(new_lines, #new_lines, prop_line)
        end
        inserted_props = true
      end
    end

    -- Add to dependencyManagement
    if not inserted_dep_mgmt then
      if line:match("<%s*dependencyManagement%s*>") then
        in_dep_mgmt = true
      elseif in_dep_mgmt and line:match("<%s*dependencies%s*>") then
        in_dep_mgmt_deps = true
      elseif in_dep_mgmt_deps and line:match("<%s*/dependencies%s*>") then
        for _, mgmt_line in ipairs(lwjgl_dep_mgmt) do
          table.insert(new_lines, #new_lines, mgmt_line)
        end
        inserted_dep_mgmt = true
      end
    end

    -- Add to dependencies
    if not inserted_deps then
      if line:match("<%s*dependencies%s*>") and not in_dep_mgmt then
        in_dependencies = true
      elseif in_dependencies and line:match("<%s*/dependencies%s*>") then
        for _, dep_line in ipairs(lwjgl_deps) do
          table.insert(new_lines, #new_lines, dep_line)
        end
        inserted_deps = true
      end
    end
  end

  if inserted_props and inserted_dep_mgmt and inserted_deps then
    vim.fn.writefile(new_lines, pom_path)
    print("LWJGL library added to pom.xml (core modules: lwjgl, glfw, opengl, stb)")
    print("Note: Change <lwjgl.natives> property if not on Linux")
    return true
  else
    print("Failed to update pom.xml - missing required sections")
    return false
  end
end

local function update_pom_for_fatjar()
  local pom_path = vim.fn.getcwd() .. "/pom.xml"
  if vim.fn.filereadable(pom_path) == 0 then
    print("No pom.xml found in current directory")
    return false
  end

  local lines = vim.fn.readfile(pom_path)
  local main_class = get_main_class()

  -- Check if shade plugin already exists in <plugins> (not pluginManagement)
  local in_plugin_management = false
  local has_shade_in_plugins = false
  for i, line in ipairs(lines) do
    if line:match("<%s*pluginManagement%s*>") then
      in_plugin_management = true
    elseif line:match("<%s*/pluginManagement%s*>") then
      in_plugin_management = false
    elseif not in_plugin_management and line:match("maven%-shade%-plugin") then
      has_shade_in_plugins = true
      break
    end
  end

  if has_shade_in_plugins then
    print("Maven Shade Plugin already configured in <plugins>")
    return true
  end

  -- Plugin configuration to add (as lines array)
  local shade_lines = {
    "      <plugin>",
    "        <groupId>org.apache.maven.plugins</groupId>",
    "        <artifactId>maven-shade-plugin</artifactId>",
    "        <version>3.5.1</version>",
    "        <executions>",
    "          <execution>",
    "            <phase>package</phase>",
    "            <goals>",
    "              <goal>shade</goal>",
    "            </goals>",
    "            <configuration>",
    "              <transformers>",
    "                <transformer implementation=\"org.apache.maven.plugins.shade.resource.ManifestResourceTransformer\">",
    "                  <mainClass>" .. main_class .. "</mainClass>",
    "                </transformer>",
    "              </transformers>",
    "              <filters>",
    "                <filter>",
    "                  <artifact>*:*</artifact>",
    "                  <excludes>",
    "                    <exclude>META-INF/*.SF</exclude>",
    "                    <exclude>META-INF/*.DSA</exclude>",
    "                    <exclude>META-INF/*.RSA</exclude>",
    "                  </excludes>",
    "                </filter>",
    "              </filters>",
    "              <finalName>${project.artifactId}-${project.version}-fat</finalName>",
    "            </configuration>",
    "          </execution>",
    "        </executions>",
    "      </plugin>"
  }

  -- Find insertion point in <plugins> section (not pluginManagement)
  local new_lines = {}
  local inserted = false
  local in_plugin_management = false
  local in_build = false
  local in_plugins = false
  local plugin_mgmt_depth = 0
  local build_indent = ""

  for i, line in ipairs(lines) do
    -- Track pluginManagement depth to handle nested tags
    if line:match("<%s*pluginManagement%s*>") then
      in_plugin_management = true
      plugin_mgmt_depth = plugin_mgmt_depth + 1
    elseif line:match("<%s*/pluginManagement%s*>") then
      plugin_mgmt_depth = plugin_mgmt_depth - 1
      if plugin_mgmt_depth == 0 then
        in_plugin_management = false
        -- After </pluginManagement>, check if we need to add <plugins>
        table.insert(new_lines, line)
        -- Look ahead to see if there's already a <plugins> section
        local has_plugins_after = false
        for j = i + 1, math.min(i + 5, #lines) do
          if lines[j]:match("<%s*plugins%s*>") and not lines[j]:match("<%s*pluginManagement") then
            has_plugins_after = true
            break
          elseif lines[j]:match("<%s*/build%s*>") then
            break
          end
        end

        -- If no <plugins> section exists after </pluginManagement>, create one
        if not has_plugins_after and not inserted then
          table.insert(new_lines, build_indent .. "    <plugins>")
          for _, plugin_line in ipairs(shade_lines) do
            table.insert(new_lines, plugin_line)
          end
          table.insert(new_lines, build_indent .. "    </plugins>")
          inserted = true
        end
        goto continue
      end
    end

    -- Only process if NOT in pluginManagement
    if not in_plugin_management then
      if line:match("<%s*build%s*>") then
        in_build = true
        build_indent = line:match("^(%s*)")
      elseif in_build and line:match("<%s*plugins%s*>") then
        in_plugins = true
      elseif in_plugins and line:match("<%s*/plugins%s*>") then
        -- Insert before </plugins> that's NOT in pluginManagement
        for _, plugin_line in ipairs(shade_lines) do
          table.insert(new_lines, plugin_line)
        end
        inserted = true
      end
    end

    table.insert(new_lines, line)
    ::continue::
  end

  if inserted then
    vim.fn.writefile(new_lines, pom_path)
    print("Maven Shade Plugin added to <plugins> for main class: " .. main_class)
    print("Run 'Maven: Package Fat Jar' to build the fat JAR")
    return true
  else
    print("Failed to update pom.xml - couldn't find proper insertion point")
    return false
  end
end

M.options = {
  {text="Maven: Build & Run", value="mvn_run"},
  {text="Maven: Build", value="mvn_build"},
  {text="Maven: Clean Build", value="mvn_clean"},
  {text="Maven: Package Fat Jar", value="mvn_pkg"},
  {text="Maven: Run Fat Jar", value="mvn_jar"},
  {text="Maven: Run with Dependencies", value="mvn_jar_cp"},
  {text="Maven: Test", value="mvn_test"},
  {text="Maven: Setup Fat Jar Build", value="mvn_setup"},
  {text="", value="separator"},
  {text="Add: Jackson JSON Library", value="add_jackson"},
  {text="Add: LWJGL Library", value="add_lwjgl"},
  {text="", value="separator"},
  {text="Quick Run", value="quick"},
  {text="Build", value="build"},
  {text="Run", value="run"},
}

function M.action(opt)
  local overseer = require("overseer")
  local cwd = vim.fn.getcwd()
  local main_cls = get_main_class()
  local lwjgl = get_lwjgl_args()
  local msg = " && echo '\\n--done--'"

  local function task(name, cmd)
    overseer.new_task({
      name = "- " .. name,
      strategy = {"orchestrator", tasks = {{
        name = "- " .. name,
        cmd = cmd .. msg,
        components = {"default_extended"}
      }}}
    }):start()
  end

  local cmds = {
    mvn_run = "mvn compile exec:java -Dexec.mainClass=" .. main_cls,
    mvn_build = "mvn compile",
    mvn_clean = "mvn clean compile",
    mvn_pkg = "mvn clean package",
    mvn_jar = "bash -c 'cd " .. cwd .. " && JAR=$(find target -type f \\( -name \"*-fat.jar\" -o -name \"*-jar-with-dependencies.jar\" \\) 2>/dev/null | head -n 1) && if [ -z \"$JAR\" ]; then echo \"No fat JAR found. Available JARs:\" && ls -la target/*.jar 2>/dev/null || echo \"No JARs in target/\"; exit 1; fi && echo \"Running: $JAR\" && java" .. lwjgl .. " -jar \"$JAR\"'",
    mvn_jar_cp = "bash -c 'cd " .. cwd .. " && java" .. lwjgl .. " -cp \"target/*:target/classes\" " .. main_cls .. "'",
    mvn_test = "mvn test",
    quick = "mvn -o compile exec:java -Dexec.mainClass=" .. main_cls,
    build = "mkdir -p bin && javac -d bin $(find . -name '*.java')",
    run = "java" .. lwjgl .. " -cp bin " .. main_cls:match("([^%.]+)$"),
  }

  if opt == "mvn_setup" then
    update_pom_for_fatjar()
  elseif opt == "add_jackson" then
    add_jackson_json()
  elseif opt == "add_lwjgl" then
    add_lwjgl_library()
  elseif cmds[opt] then
    task(opt:gsub("_", " "), cmds[opt])
  end
end

return M
