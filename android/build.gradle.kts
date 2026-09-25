buildscript {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://api.mapbox.com/downloads/v2/releases/maven")
            authentication {
                create<BasicAuthentication>("basic")
            }
            credentials {
                username = "mapbox"
                password = (providers.gradleProperty("MAPBOX_DOWNLOADS_TOKEN").orNull)
            }
        }
    }
    dependencies {
        classpath("com.google.gms:google-services:4.4.2")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://api.mapbox.com/downloads/v2/releases/maven")
            authentication {
                create<BasicAuthentication>("basic")
            }
            credentials {
                username = "mapbox"
                password = (providers.gradleProperty("SDK_REGISTRY_TOKEN").orNull)
            }
        }
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
}

subprojects {
    project.evaluationDependsOn(":app")
}

// Google Play requires 16 KB memory-page support. Mapbox ships the same SDK version
// built for it as "-ndk27" artifacts; use those instead of the ones the
// mapbox_maps_flutter plugin asks for.
subprojects {
    configurations.all {
        resolutionStrategy.dependencySubstitution {
            substitute(module("com.mapbox.maps:android"))
                .using(module("com.mapbox.maps:android-ndk27:11.15.0"))
                .because("16 KB page size support required by Google Play")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
