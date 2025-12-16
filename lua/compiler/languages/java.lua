--- Java language actions
local M = {}

local function get_main_class()
  local pom = vim.fn.getcwd() .. "/pom.xml"
  if vim.fn.filereadable(pom) == 0 then return nil end
  for _, line in ipairs(vim.fn.readfile(pom)) do
    local match = line:match("<mainClass>(.-)</mainClass>")
    if match then return match end
  end
  return nil
end

local function detect_main_class()
  local maven_src = vim.fn.getcwd() .. "/src/main/java"
  local paths = vim.fn.isdirectory(maven_src) == 1 and {maven_src} or {vim.fn.getcwd()}

  for _, path in ipairs(paths) do
    for _, file in ipairs(vim.fn.globpath(path, "**/*.java", false, true)) do
      if vim.fn.filereadable(file) == 1 then
        local pkg, cls, has_main = nil, nil, false
        for _, line in ipairs(vim.fn.readfile(file)) do
          pkg = pkg or line:match("^%s*package%s+([%w%.]+)%s*;")
          cls = cls or line:match("^%s*public%s+class%s+(%w+)")
          has_main = has_main or line:match("public%s+static%s+void%s+main%s*%(") or line:match("static%s+public%s+void%s+main%s*%(")
          if cls and has_main then return pkg and pkg .. "." .. cls or cls end
        end
      end
    end
  end
  return nil
end

local function get_main_class_with_detection()
  return detect_main_class() or get_main_class() or "com.jless.chess.App"
end

M.options = {
  {text="Maven: Build & Run", value="maven_build_run"}, {text="Maven: Build (compile)", value="maven_build"},
  {text="Maven: Run", value="maven_run"}, {text="Maven: Clean", value="maven_clean"},
  {text="Maven: Package (jar)", value="maven_package"}, {text="Maven: Package Fat Jar (assembly)", value="maven_package_assembly"},
  {text="Maven: Package Fat Jar (shade)", value="maven_package_shade"}, {text="Maven: Run Packaged Jar", value="maven_run_jar"},
  {text="Maven: Test", value="maven_test"}, {text="Maven: Clean Install", value="maven_clean_install"},
  {text="", value="separator"}, {text="Build and run program (class)", value="option1"},
  {text="Build program (class)", value="option2"}, {text="Run program (class)", value="option3"},
  {text="Build solution (class)", value="option4"}, {text="", value="separator"},
  {text="Build and run program (jar)", value="option5"}, {text="Build program (jar)", value="option6"},
  {text="Run program (jar)", value="option7"}, {text="Build solution (jar)", value="option8"},
  {text="", value="separator"}, {text="Run REPL", value="option9"}
}

function M.action(opt)
  local utils = require("compiler.utils")
  local overseer = require("overseer")
  local entry = utils.os_path(vim.fn.getcwd() .. "/Main.java")
  local files = utils.find_files_to_compile(entry, "*.java")
  local out_dir = utils.os_path(vim.fn.getcwd() .. "/bin/")
  local out = utils.os_path(vim.fn.getcwd() .. "/bin/Main")
  local out_name = "Main"
  local args = "-Xlint:all"
  local msg = "--task finished--"
  local main_cls = get_main_class_with_detection()
  local function echo(p) return " && echo \"\\n" .. p .. "\"" end

  local function maven_task(name, cmd)
    overseer.new_task({name="- Maven " .. name, strategy={"orchestrator",
      tasks={{name="- Maven " .. name, cmd=cmd .. echo(vim.fn.getcwd()) .. " && echo \"" .. msg .. "\"",
      components={"default_extended"}}}}}):start()
  end

  if opt == "maven_build_run" then
    maven_task("build & run", "mvn clean compile exec:java -Dexec.mainClass=" .. main_cls)
  elseif opt == "maven_build" then maven_task("build", "mvn compile")
  elseif opt == "maven_run" then maven_task("run", "mvn exec:java -Dexec.mainClass=" .. main_cls)
  elseif opt == "maven_clean" then maven_task("clean", "mvn clean")
  elseif opt == "maven_package" then maven_task("package", "mvn clean package")
  elseif opt == "maven_package_assembly" then
    overseer.new_task({name="- Maven package fat jar (assembly)", strategy={"orchestrator",
      tasks={{name="- Maven assembly:single",
      cmd="mvn clean compile assembly:single" .. echo(vim.fn.getcwd()) .. " && echo \"Fat jar created with maven-assembly-plugin\" && echo \"" .. msg .. "\"",
      components={"default_extended"}}}}}):start()
  elseif opt == "maven_package_shade" then
    overseer.new_task({name="- Maven package fat jar (shade)", strategy={"orchestrator",
      tasks={{name="- Maven shade",
      cmd="mvn clean package shade:shade" .. echo(vim.fn.getcwd()) .. " && echo \"Fat jar created with maven-shade-plugin\" && echo \"" .. msg .. "\"",
      components={"default_extended"}}}}}):start()
  elseif opt == "maven_run_jar" then
    overseer.new_task({name="- Maven run packaged jar", strategy={"orchestrator",
      tasks={{name="- Run jar from target/",
      cmd="cd " .. vim.fn.getcwd() .. " && JAR=$(find target -name '*.jar' -not -name '*-sources.jar' -not -name '*-javadoc.jar' | head -n 1) && if [ -n \"$JAR\" ]; then java -jar \"$JAR\"; else echo 'No jar found in target/'; exit 1; fi && echo \"" .. msg .. "\"",
      components={"default_extended"}}}}}):start()
  elseif opt == "maven_test" then maven_task("test", "mvn test")
  elseif opt == "maven_clean_install" then maven_task("clean install", "mvn clean install")
  elseif opt == "option10" then maven_task("build & run", "mvn clean compile exec:java -Dexec.mainClass=" .. main_cls)
  elseif opt == "option11" then maven_task("build", "mvn clean compile")
  elseif opt == "option12" then maven_task("run", "mvn exec:java -Dexec.mainClass=" .. main_cls)

  elseif opt == "option1" then
    overseer.new_task({name="- Java compiler", strategy={"orchestrator",
      tasks={{name="- Build & run program (class) → \"" .. entry .. "\"",
      cmd="rm -f \"" .. out_dir .. "*.class\" || true && mkdir -p \"" .. out_dir .. "\" && javac -d \"" .. out_dir .. "\" " .. args .. " " .. files .. " && java -cp \"" .. out_dir .. "\" " .. out_name .. " && echo \"" .. entry .. "\" && echo \"" .. msg .. "\"",
      components={"default_extended"}}}}}):start()
  elseif opt == "option2" then
    overseer.new_task({name="- Java compiler", strategy={"orchestrator",
      tasks={{name="- Build program (class) → \"" .. entry .. "\"",
      cmd="rm -f \"" .. out_dir .. "/*.class\" || true && mkdir -p \"" .. out_dir .. "\" && javac -d \"" .. out_dir .. "\" " .. args .. " " .. files .. " && echo \"" .. entry .. "\" && echo \"" .. msg .. "\"",
      components={"default_extended"}}}}}):start()
  elseif opt == "option3" then
    overseer.new_task({name="- Java compiler", strategy={"orchestrator",
      tasks={{name="- Run program (class) → \"" .. out .. ".class\"",
      cmd="java -cp \"" .. out_dir .. "\" " .. out_name .. " && echo \"" .. out .. ".class\" && echo \"" .. msg .. "\"",
      components={"default_extended"}}}}}):start()
  elseif opt == "option4" then
    local tasks, execs = {}, {}
    local sol = utils.get_solution_file()
    if sol then
      local cfg = utils.parse_solution_file(sol)
      for e, v in pairs(cfg) do
        if e ~= "executables" then
          entry = utils.os_path(v.entry_point)
          files = utils.find_files_to_compile(entry, "*.java")
          out = utils.os_path(v.output)
          out_dir = utils.os_path(out:match("^(.-[/\\])[^/\\]*$"))
          args = v.arguments or args
          table.insert(tasks, {name="- Build program (class) → \"" .. entry .. "\"",
            cmd="rm -f \"" .. out_dir .. "/*.class\" || true && mkdir -p \"" .. out_dir .. "\" && javac -d \"" .. out_dir .. "\" " .. args .. " " .. files .. " && echo \"" .. entry .. "\" && echo \"" .. msg .. "\"",
            components={"default_extended"}})
        end
      end
      if cfg.executables then
        for _, ex in pairs(cfg.executables) do
          out_dir = utils.os_path(ex:match("^(.-[/\\])[^/\\]*$"))
          out_name = vim.fn.fnamemodify(ex, ':t:r')
          table.insert(execs, {name="- Run program (class) → \"" .. ex .. "\"",
            cmd="java -cp \"" .. out_dir .. "\" " .. out_name .. " && echo \"" .. out_dir .. out_name .. ".class\" && echo \"" .. msg .. "\"",
            components={"default_extended"}})
        end
      end
      overseer.new_task({name="- Java compiler", strategy={"orchestrator", tasks={tasks, execs}}}):start()
    else
      for _, ep in ipairs(utils.find_files(vim.fn.getcwd(), "Main.java")) do
        entry = utils.os_path(ep)
        files = utils.find_files_to_compile(entry, "*.java")
        out_dir = utils.os_path(entry:match("^(.-[/\\])[^/\\]*$") .. "bin")
        table.insert(tasks, {name="- Build program (class) → \"" .. entry .. "\"",
          cmd="rm -f \"" .. out_dir .. "/*.class\" || true && mkdir -p \"" .. out_dir .. "\" && javac -d \"" .. out_dir .. "\" " .. args .. " " .. files .. " && echo \"" .. entry .. "\" && echo \"" .. msg .. "\"",
          components={"default_extended"}})
      end
      overseer.new_task({name="- Java compiler", strategy={"orchestrator", tasks=tasks}}):start()
    end

  elseif opt == "option5" then
    overseer.new_task({name="- Java compiler", strategy={"orchestrator",
      tasks={{name="- Build & run program (jar) → \"" .. entry .. "\"",
      cmd="rm -f \"" .. out .. ".jar\" || true && mkdir -p \"" .. out_dir .. "\" && jar cfe \"" .. out .. ".jar\" " .. out_name .. " -C \"" .. out_dir .. "\" . && java -jar \"" .. out .. ".jar\" && echo \"" .. entry .. "\" && echo \"" .. msg .. "\"",
      components={"default_extended"}}}}}):start()
  elseif opt == "option6" then
    overseer.new_task({name="- Java compiler", strategy={"orchestrator",
      tasks={{name="- Build program (jar) → \"" .. entry .. "\"",
      cmd="rm -f \"" .. out .. ".jar\" || true && mkdir -p \"" .. out_dir .. "\" && jar cfe \"" .. out .. ".jar\" " .. out_name .. " -C \"" .. out_dir .. "\" . && echo \"" .. entry .. "\" && echo \"" .. msg .. "\"",
      components={"default_extended"}}}}}):start()
  elseif opt == "option7" then
    overseer.new_task({name="- Java compiler", strategy={"orchestrator",
      tasks={{name="- Run program (jar) → \"" .. out .. ".jar\"",
      cmd="java -jar \"" .. out .. ".jar\" && echo \"" .. out .. ".jar\" && echo \"" .. msg .. "\"",
      components={"default_extended"}}}}}):start()
  elseif opt == "option8" then
    local tasks, execs = {}, {}
    local sol = utils.get_solution_file()
    if sol then
      local cfg = utils.parse_solution_file(sol)
      for e, v in pairs(cfg) do
        if e ~= "executables" then
          entry = utils.os_path(v.entry_point)
          files = utils.find_files_to_compile(entry, "*.java")
          out = utils.os_path(v.output)
          out_dir = utils.os_path(out:match("^(.-[/\\])[^/\\]*$"))
          out_name = vim.fn.fnamemodify(out, ':t:r')
          args = v.arguments or args
          table.insert(tasks, {name="- Build program (jar) → \"" .. entry .. "\"",
            cmd="rm -f \"" .. out .. "\" || true && mkdir -p \"" .. out_dir .. "\" && jar cfe \"" .. out .. "\" " .. out_name .. " -C \"" .. out_dir .. "\" . && echo \"" .. entry .. "\" && echo \"" .. msg .. "\"",
            components={"default_extended"}})
        end
      end
      if cfg.executables then
        for _, ex in pairs(cfg.executables) do
          ex = utils.os_path(ex, true)
          table.insert(execs, {name="- Run program (jar) → \"" .. ex .. "\"",
            cmd="java -jar " .. ex .. " && echo " .. ex .. " && echo \"" .. msg .. "\"",
            components={"default_extended"}})
        end
      end
      overseer.new_task({name="- Java compiler", strategy={"orchestrator", tasks={tasks, execs}}}):start()
    else
      for _, ep in ipairs(utils.find_files(vim.fn.getcwd(), "Main.java")) do
        entry = utils.os_path(ep)
        out_dir = utils.os_path(entry:match("^(.-[/\\])[^/\\]*$") .. "bin")
        out = utils.os_path(out_dir .. "/Main")
        table.insert(tasks, {name="- Build program (jar) → \"" .. entry .. "\"",
          cmd="rm -f \"" .. out .. ".jar\" || true && mkdir -p \"" .. out_dir .. "\" && jar cfe \"" .. out .. ".jar\" " .. out_name .. " -C \"" .. out_dir .. "\" . && echo \"" .. entry .. "\" && echo \"" .. msg .. "\"",
          components={"default_extended"}})
      end
      overseer.new_task({name="- Java compiler", strategy={"orchestrator", tasks=tasks}}):start()
    end

  elseif opt == "option9" then
    overseer.new_task({name="- Java compiler", strategy={"orchestrator",
      tasks={{name="- Start REPL",
      cmd="echo 'To exit the REPL enter /exit' && jshell && echo \"" .. msg .. "\"",
      components={"default_extended"}}}}}):start()
  end
end

return M
