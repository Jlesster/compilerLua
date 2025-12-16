--- Java language actions

local M = {}

-- Helper: read <mainClass> from pom.xml
local function get_main_class()
  local pom_path = vim.fn.getcwd() .. "/pom.xml"
  if vim.fn.filereadable(pom_path) == 0 then
    return nil
  end
  local lines = vim.fn.readfile(pom_path)
  for _, line in ipairs(lines) do
    local match = line:match("<mainClass>(.-)</mainClass>")
    if match then
      return match
    end
  end
  return nil
end

-- Helper: detect main class by searching for public static void main
local function detect_main_class()
  -- Search for Java files with main method in src/main/java (Maven structure)
  local maven_src = vim.fn.getcwd() .. "/src/main/java"
  local search_paths = {}

  if vim.fn.isdirectory(maven_src) == 1 then
    table.insert(search_paths, maven_src)
  else
    -- Fallback to current directory
    table.insert(search_paths, vim.fn.getcwd())
  end

  for _, search_path in ipairs(search_paths) do
    local java_files = vim.fn.globpath(search_path, "**/*.java", false, true)

    for _, file in ipairs(java_files) do
      if vim.fn.filereadable(file) == 1 then
        local lines = vim.fn.readfile(file)
        local package_name = nil
        local class_name = nil
        local has_main = false

        for _, line in ipairs(lines) do
          -- Extract package name
          if not package_name then
            local pkg = line:match("^%s*package%s+([%w%.]+)%s*;")
            if pkg then
              package_name = pkg
            end
          end

          -- Extract class name (public class only)
          if not class_name then
            local cls = line:match("^%s*public%s+class%s+(%w+)")
            if cls then
              class_name = cls
            end
          end

          -- Check for main method
          if line:match("public%s+static%s+void%s+main%s*%(") or
             line:match("static%s+public%s+void%s+main%s*%(") then
            has_main = true
          end

          -- If we found everything, construct the fully qualified class name
          if class_name and has_main then
            if package_name then
              return package_name .. "." .. class_name
            else
              return class_name
            end
          end
        end
      end
    end
  end

  return nil
end

-- Helper: get main class with detection fallback
local function get_main_class_with_detection()
  -- First try to detect from source files
  local detected = detect_main_class()
  if detected then
    return detected
  end

  -- Then try pom.xml
  local from_pom = get_main_class()
  if from_pom then
    return from_pom
  end

  -- Final fallback
  return "com.jless.chess.App"
end

--- Frontend - options displayed on telescope
M.options = {
  { text = "Maven: Build & Run", value = "maven_build_run" },
  { text = "Maven: Build (compile)", value = "maven_build" },
  { text = "Maven: Run", value = "maven_run" },
  { text = "Maven: Clean", value = "maven_clean" },
  { text = "Maven: Package (jar)", value = "maven_package" },
  { text = "Maven: Package Fat Jar (assembly)", value = "maven_package_assembly" },
  { text = "Maven: Package Fat Jar (shade)", value = "maven_package_shade" },
  { text = "Maven: Run Packaged Jar", value = "maven_run_jar" },
  { text = "Maven: Test", value = "maven_test" },
  { text = "Maven: Clean Install", value = "maven_clean_install" },
  { text = "", value = "separator" },
  { text = "Build and run program (class)", value = "option1" },
  { text = "Build program (class)", value = "option2" },
  { text = "Run program (class)", value = "option3" },
  { text = "Build solution (class)", value = "option4" },
  { text = "", value = "separator" },
  { text = "Build and run program (jar)", value = "option5" },
  { text = "Build program (jar)", value = "option6" },
  { text = "Run program (jar)", value = "option7" },
  { text = "Build solution (jar)", value = "option8" },
  { text = "", value = "separator" },
  { text = "Run REPL", value = "option9" },
}

--- Backend - overseer tasks performed on option selected

function M.action(selected_option)
  local utils = require("compiler.utils")
  local overseer = require("overseer")
  local entry_point = utils.os_path(vim.fn.getcwd() .. "/Main.java")
  local files = utils.find_files_to_compile(entry_point, "*.java")
  local output_dir = utils.os_path(vim.fn.getcwd() .. "/bin/")
  local output = utils.os_path(vim.fn.getcwd() .. "/bin/Main")
  local output_filename = "Main"
  local arguments = "-Xlint:all"
  local final_message = "--task finished--"

  -- Get the main class with automatic detection
  local main_class = get_main_class_with_detection()

  -- Helper: echo entry point with newline
  local function echo_path(path)
    return " && echo \"\\n" .. path .. "\""
  end

  --=========================== Maven Support (Full) ============================--

  if selected_option == "maven_build_run" then
    local task = overseer.new_task({
      name = "- Maven build & run",
      strategy = { "orchestrator",
        tasks = {{
          name = "- Maven compile & exec",
          cmd = "mvn clean compile exec:java -Dexec.mainClass=" .. main_class ..
                echo_path(vim.fn.getcwd()) ..
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        }}
      }
    })
    task:start()

  elseif selected_option == "maven_build" then
    local task = overseer.new_task({
      name = "- Maven build",
      strategy = { "orchestrator",
        tasks = {{
          name = "- Maven compile",
          cmd = "mvn compile" ..
                echo_path(vim.fn.getcwd()) ..
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        }}
      }
    })
    task:start()

  elseif selected_option == "maven_run" then
    local task = overseer.new_task({
      name = "- Maven run",
      strategy = { "orchestrator",
        tasks = {{
          name = "- Maven exec",
          cmd = "mvn exec:java -Dexec.mainClass=" .. main_class ..
                echo_path(vim.fn.getcwd()) ..
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        }}
      }
    })
    task:start()

  elseif selected_option == "maven_clean" then
    local task = overseer.new_task({
      name = "- Maven clean",
      strategy = { "orchestrator",
        tasks = {{
          name = "- Maven clean",
          cmd = "mvn clean" ..
                echo_path(vim.fn.getcwd()) ..
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        }}
      }
    })
    task:start()

  elseif selected_option == "maven_package" then
    local task = overseer.new_task({
      name = "- Maven package",
      strategy = { "orchestrator",
        tasks = {{
          name = "- Maven package (jar)",
          cmd = "mvn clean package" ..
                echo_path(vim.fn.getcwd()) ..
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        }}
      }
    })
    task:start()

  elseif selected_option == "maven_package_assembly" then
    local task = overseer.new_task({
      name = "- Maven package fat jar (assembly)",
      strategy = { "orchestrator",
        tasks = {{
          name = "- Maven assembly:single",
          cmd = "mvn clean compile assembly:single" ..
                echo_path(vim.fn.getcwd()) ..
                " && echo \"Fat jar created with maven-assembly-plugin\"" ..
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        }}
      }
    })
    task:start()

  elseif selected_option == "maven_package_shade" then
    local task = overseer.new_task({
      name = "- Maven package fat jar (shade)",
      strategy = { "orchestrator",
        tasks = {{
          name = "- Maven shade",
          cmd = "mvn clean package shade:shade" ..
                echo_path(vim.fn.getcwd()) ..
                " && echo \"Fat jar created with maven-shade-plugin\"" ..
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        }}
      }
    })
    task:start()

  elseif selected_option == "maven_run_jar" then
    local task = overseer.new_task({
      name = "- Maven run packaged jar",
      strategy = { "orchestrator",
        tasks = {{
          name = "- Run jar from target/",
          cmd = "cd " .. vim.fn.getcwd() ..
                " && JAR=$(find target -name '*.jar' -not -name '*-sources.jar' -not -name '*-javadoc.jar' | head -n 1)" ..
                " && if [ -n \"$JAR\" ]; then java -jar \"$JAR\"; else echo 'No jar found in target/'; exit 1; fi" ..
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        }}
      }
    })
    task:start()

  elseif selected_option == "maven_test" then
    local task = overseer.new_task({
      name = "- Maven test",
      strategy = { "orchestrator",
        tasks = {{
          name = "- Maven test",
          cmd = "mvn test" ..
                echo_path(vim.fn.getcwd()) ..
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        }}
      }
    })
    task:start()

  elseif selected_option == "maven_clean_install" then
    local task = overseer.new_task({
      name = "- Maven clean install",
      strategy = { "orchestrator",
        tasks = {{
          name = "- Maven clean install",
          cmd = "mvn clean install" ..
                echo_path(vim.fn.getcwd()) ..
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        }}
      }
    })
    task:start()

  --========================== Legacy Maven Options (Kept for backward compatibility) ==============--
  elseif selected_option == "option10" then -- Build & run with Maven
    local task = overseer.new_task({
      name = "- Maven build & run",
      strategy = { "orchestrator",
        tasks = {{
          name = "- Maven compile & exec",
          cmd = "mvn clean compile exec:java -Dexec.mainClass=" .. main_class ..
                echo_path(vim.fn.getcwd()) ..
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        }}
      }
    })
    task:start()

  elseif selected_option == "option11" then -- Build only
    local task = overseer.new_task({
      name = "- Maven build",
      strategy = { "orchestrator",
        tasks = {{
          name = "- Maven compile",
          cmd = "mvn clean compile" ..
                echo_path(vim.fn.getcwd()) ..
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        }}
      }
    })
    task:start()

  elseif selected_option == "option12" then -- Run only
    local task = overseer.new_task({
      name = "- Maven run",
      strategy = { "orchestrator",
        tasks = {{
          name = "- Maven exec",
          cmd = "mvn exec:java -Dexec.mainClass=" .. main_class ..
                echo_path(vim.fn.getcwd()) ..
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        }}
      }
    })
    task:start()
  end

  --========================== Build as class ===============================--
  if selected_option == "option1" then
    local task = overseer.new_task({
      name = "- Java compiler",
      strategy = { "orchestrator",
        tasks = {{ name = "- Build & run program (class) → \"" .. entry_point .. "\"",
          cmd = "rm -f \"" .. output_dir .. "*.class\"" .. " || true" ..                   -- clean
                " && mkdir -p \"" .. output_dir .. "\"" ..                                 -- mkdir
                " && javac -d \"" .. output_dir .. "\" " .. arguments .. " " .. files ..   -- compile bytecode (.class)
                " && java -cp \"" .. output_dir .. "\" " .. output_filename ..             -- run
                " && echo \"" .. entry_point .. "\"" ..                                    -- echo
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        },},},})
    task:start()
  elseif selected_option == "option2" then
    local task = overseer.new_task({
      name = "- Java compiler",
      strategy = { "orchestrator",
        tasks = {{ name = "- Build program (class) → \"" .. entry_point .. "\"",
          cmd = "rm -f \"" .. output_dir .. "/*.class\"" .. " || true" ..                  -- clean
                " && mkdir -p \"" .. output_dir .. "\"" ..                                 -- mkdir
                " && javac -d \"" .. output_dir .. "\" " .. arguments .. " "  .. files ..  -- compile bytecode (.class)
                " && echo \"" .. entry_point .. "\"" ..                                    -- echo
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        },},},})
    task:start()
  elseif selected_option == "option3" then
    local task = overseer.new_task({
      name = "- Java compiler",
      strategy = { "orchestrator",
        tasks = {{ name = "- Run program (class) → \"" .. output .. ".class\"",
          cmd = "java -cp \"" .. output_dir .. "\" " .. output_filename ..                 -- run
                " && echo \"" .. output .. ".class\"" ..                                   -- echo
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
        files = utils.find_files_to_compile(entry_point, "*.java")
        output = utils.os_path(variables.output)
        output_dir = utils.os_path(output:match("^(.-[/\\])[^/\\]*$"))
        arguments = variables.arguments or arguments -- optiona
        task = { name = "- Build program (class) → \"" .. entry_point .. "\"",
          cmd = "rm -f \"" .. output_dir .. "/*.class\"" .. " || true" ..                  -- clean
                " && mkdir -p \"" .. output_dir .. "\"" ..                                 -- mkdir
                " && javac -d \"" .. output_dir .. "\" " .. arguments .. " "  .. files ..  -- compile bytecode
                " && echo \"" .. entry_point .. "\""  ..                                   -- echo
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        }
        table.insert(tasks, task) -- store all the tasks we've created
        ::continue::
      end

      local solution_executables = config["executables"]
      if solution_executables then
        for entry, executable in pairs(solution_executables) do
          output_dir = utils.os_path(executable:match("^(.-[/\\])[^/\\]*$"))
          output_filename = vim.fn.fnamemodify(executable, ':t:r')
          task = { name = "- Run program (class) → \"" .. executable .. "\"",
            cmd = "java -cp \"" .. output_dir .. "\" " .. output_filename ..               -- run
                  " && echo \"" .. output_dir .. output_filename .. ".class\"" ..          -- echo
                  " && echo \"" .. final_message .. "\"",
            components = { "default_extended" }
          }
          table.insert(executables, task) -- store all the executables we've created
        end
      end

      task = overseer.new_task({
        name = "- Java compiler", strategy = { "orchestrator",
          tasks = {
            tasks,        -- Build all the programs in the solution in parallel
            executables   -- Then run the solution executable(s)
          }}})
      task:start()

    else -- If no .solution file
      -- Create a list of all entry point files in the working directory
      entry_points = utils.find_files(vim.fn.getcwd(), "Main.java")

      for _, entry_point in ipairs(entry_points) do
        entry_point = utils.os_path(entry_point)
        files = utils.find_files_to_compile(entry_point, "*.java")
        output_dir = utils.os_path(entry_point:match("^(.-[/\\])[^/\\]*$") .. "bin")       -- entry_point/bin
        task = { name = "- Build program (class) → \"" .. entry_point .. "\"",
          cmd = "rm -f \"" .. output_dir .. "/*.class\"" .. " || true" ..                  -- clean
                " && mkdir -p \"" .. output_dir .."\"" ..                                  -- mkdir
                " && javac -d \"" .. output_dir .. "\" " .. arguments .. " "  .. files ..  -- compile bytecode
                " && echo \"" .. entry_point .. "\"" ..                                    -- echo
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        }
        table.insert(tasks, task) -- store all the tasks we've created
      end

      task = overseer.new_task({ -- run all tasks we've created in parallel
        name = "- Java compiler", strategy = { "orchestrator", tasks = tasks }
      })
      task:start()
    end








  --=========================== Build as jar ================================--
  elseif selected_option == "option5" then
    local task = overseer.new_task({
      name = "- Java compiler",
      strategy = { "orchestrator",
        tasks = {{ name = "- Build & run program (jar) → \"" .. entry_point .. "\"",
          cmd = "rm -f \"" .. output .. ".jar\"" .. " || true" ..                                           -- clean
                " && mkdir -p \"" .. output_dir .. "\"" ..                                                  -- mkdir
                " && jar cfe \"" .. output .. ".jar\" " .. output_filename .. " -C \"" .. output_dir .. "\" . " ..  -- compile bytecode (.jar)
                " && java -jar \"" .. output .. ".jar\"" ..                                                 -- run
                " && echo \"" .. entry_point .. "\"" ..                                                     -- echo
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        },},},})
    task:start()
  elseif selected_option == "option6" then
    local task = overseer.new_task({
      name = "- Java compiler",
      strategy = { "orchestrator",
        tasks = {{ name = "- Build program (jar) → \"" .. entry_point .. "\"",
          cmd = "rm -f \"" .. output .. ".jar\"" .. " || true" ..                                           -- clean
                " && mkdir -p \"" .. output_dir .. "\"" ..                                                  -- mkdir
                " && jar cfe \"" .. output .. ".jar\" " .. output_filename .. " -C \"" .. output_dir .. "\" . " ..  -- compile bytecode (.jar)
                " && echo \"" .. entry_point .. "\"" ..                                                     -- echo
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        },},},})
    task:start()
  elseif selected_option == "option7" then
    local task = overseer.new_task({
      name = "- Java compiler",
      strategy = { "orchestrator",
        tasks = {{ name = "- Run program (jar) → \"" .. output .. ".jar\"",
          cmd = "java -jar \"" .. output .. ".jar\"" ..                                                     -- run
                " && echo \"" .. output .. ".jar\""  ..                                                     -- echo
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        },},},})
    task:start()
  elseif selected_option == "option8" then
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
        files = utils.find_files_to_compile(entry_point, "*.java")
        output = utils.os_path(variables.output)
        output_dir = utils.os_path(output:match("^(.-[/\\])[^/\\]*$"))
        output_filename = vim.fn.fnamemodify(output, ':t:r')
        arguments = variables.arguments or arguments -- optional
        task = { name = "- Build program (jar) → \"" .. entry_point .. "\"",
          cmd = "rm -f \"" .. output .. "\" || true" ..                                                     -- clean
                " && mkdir -p \"" .. output_dir .. "\"" ..                                                  -- mkdir
                " && jar cfe \"" .. output .. "\" " .. output_filename .. " -C \"" .. output_dir .. "\" . " ..  -- compile bytecode (jar)
                " && echo \"" .. entry_point .. "\"" ..                                                     -- echo
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        }
        table.insert(tasks, task) -- store all the tasks we've created
        ::continue::
      end

      local solution_executables = config["executables"]
      if solution_executables then
        for entry, executable in pairs(solution_executables) do
          executable = utils.os_path(executable, true)
          task = { name = "- Run program (jar) → \"" .. executable .. "\"",
            cmd = "java -jar " .. executable ..                                                             -- run
                  " && echo " .. executable ..                                                              -- echo
                  " && echo \"" .. final_message .. "\"",
            components = { "default_extended" }
          }
          table.insert(executables, task) -- store all the executables we've created
        end
      end

      task = overseer.new_task({
        name = "- Java compiler", strategy = { "orchestrator",
          tasks = {
            tasks,        -- Build all the programs in the solution in parallel
            executables   -- Then run the solution executable(s)
          }}})
      task:start()

    else -- If no .solution file
      -- Create a list of all entry point files in the working directory
      entry_points = utils.find_files(vim.fn.getcwd(), "Main.java")

      for _, entry_point in ipairs(entry_points) do
        entry_point = utils.os_path(entry_point)
        output_dir = utils.os_path(entry_point:match("^(.-[/\\])[^/\\]*$") .. "bin")                            -- entry_point/bin
        output = utils.os_path(output_dir .. "/Main")                                                           -- entry_point/bin/Main.jar
        task = { name = "- Build program (jar) → \"" .. entry_point .. "\"",
          cmd = "rm -f \"" .. output .. ".jar\" " .. " || true" ..                                              -- clean
                " && mkdir -p \"" .. output_dir .. "\"" ..                                                      -- mkdir
                " && jar cfe \"" .. output .. ".jar\" " .. output_filename .. " -C \"" .. output_dir .. "\" . " ..  -- compile bytecode (jar)
                " && echo \"" .. entry_point .. "\"" ..                                                         -- echo
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        }
        table.insert(tasks, task) -- store all the tasks we've created
      end

      task = overseer.new_task({ -- run all tasks we've created in parallel
        name = "- Java compiler", strategy = { "orchestrator", tasks = tasks }
      })
      task:start()
    end








  --========================== MISC ===============================--
  elseif selected_option == "option9" then
    local task = overseer.new_task({
      name = "- Java compiler",
      strategy = { "orchestrator",
        tasks = {{ name = "- Start REPL",
          cmd = "echo 'To exit the REPL enter /exit'" ..                     -- echo
                " && jshell " ..                                             -- run (repl)
                " && echo \"" .. final_message .. "\"",
          components = { "default_extended" }
        },},},})
    task:start()
  end
end

return M
