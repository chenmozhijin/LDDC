allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    if (project.name == "integration_test") {
        afterEvaluate {
            val apiConfiguration = configurations.getByName("api")
            val misplacedTestDependencies = apiConfiguration.dependencies
                .filter { dependency -> dependency.group?.startsWith("androidx.test") == true }
                .toList()
            misplacedTestDependencies.forEach(apiConfiguration.dependencies::remove)

            // Flutter integration_test 当前把 runner、rules 和 Espresso 声明为 api，导致这些
            // 测试框架被打入主 Debug APK。AndroidTest 随后跨 APK 去重类，却保留测试 Activity
            // manifest，最终在独立测试进程触发 ActivityInvoker 类加载崩溃。插件源码只需在
            // 编译期看到这些类型；运行期依赖由 app 的 androidTestImplementation 独立提供。
            dependencies.add("compileOnly", "androidx.test:runner:1.7.0")
            dependencies.add("compileOnly", "androidx.test:rules:1.7.0")
            dependencies.add("compileOnly", "androidx.test.espresso:espresso-core:3.7.0")
        }

        configurations.configureEach {
            if (name == "debugCompileClasspath") {
                // compileOnly 使用固定版本，避免 Flutter SDK 中的动态版本触发 metadata 请求。
                resolutionStrategy.force(
                    "androidx.test:runner:1.7.0",
                    "androidx.test:rules:1.7.0",
                    "androidx.test.espresso:espresso-core:3.7.0",
                )
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
