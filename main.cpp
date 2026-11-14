#include <cerrno>
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

#ifdef _WIN32
#include <process.h>
#else
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
extern char** environ;
#endif

namespace {

namespace fs = std::filesystem;

void printUsage(const char* executable) {
    std::cout
        << "OpenBurn - optical disc image and burning utility\n\n"
        << "Usage:\n"
        << "  " << executable << " devices\n"
        << "  " << executable << " image <source-directory> <output.iso>\n"
        << "  " << executable << " burn <image.iso> <device> [--yes]\n"
        << "  " << executable << " verify <image.iso>\n";
}

int runXorriso(const std::vector<std::string>& arguments) {
    std::vector<char*> argv;
    argv.reserve(arguments.size() + 1);
    for (const auto& argument : arguments) {
        argv.push_back(const_cast<char*>(argument.c_str()));
    }
    argv.push_back(nullptr);

#ifdef _WIN32
    const auto result = _spawnvp(_P_WAIT, "xorriso", argv.data());
    if (result == -1) {
        if (errno == ENOENT) {
            std::cerr << "OpenBurn requires xorriso, but it was not found in PATH.\n";
        } else {
            std::cerr << "Could not start xorriso (error " << errno << ").\n";
        }
        return 1;
    }
    return static_cast<int>(result);
#else
    pid_t processId = 0;
    const int spawnError = posix_spawnp(&processId, "xorriso", nullptr, nullptr, argv.data(), environ);
    if (spawnError != 0) {
        if (spawnError == ENOENT) {
            std::cerr << "OpenBurn requires xorriso, but it was not found in PATH.\n";
        } else {
            std::cerr << "Could not start xorriso (error " << spawnError << ").\n";
        }
        return 1;
    }

    int status = 0;
    while (waitpid(processId, &status, 0) == -1) {
        if (errno == EINTR) {
            continue;
        }
        std::cerr << "Could not wait for xorriso to finish.\n";
        return 1;
    }
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    return 1;
#endif
}

bool isRegularFile(const fs::path& path) {
    std::error_code error;
    if (!fs::is_regular_file(path, error)) {
        std::cerr << "Not a readable regular file: " << path << '\n';
        return false;
    }
    return true;
}

bool isInside(const fs::path& parent, const fs::path& child) {
    auto parentPart = parent.begin();
    auto childPart = child.begin();
    while (parentPart != parent.end() && childPart != child.end() &&
           *parentPart == *childPart) {
        ++parentPart;
        ++childPart;
    }
    return parentPart == parent.end();
}

int createImage(const fs::path& sourcePath, const fs::path& outputPath) {
    std::error_code error;
    const auto source = fs::canonical(sourcePath, error);
    if (error || !fs::is_directory(source)) {
        std::cerr << "Source must be an existing directory: " << sourcePath << '\n';
        return 1;
    }

    auto outputParent = outputPath.parent_path();
    if (outputParent.empty()) {
        outputParent = fs::current_path();
    }
    const auto canonicalParent = fs::canonical(outputParent, error);
    if (error || !fs::is_directory(canonicalParent)) {
        std::cerr << "Output directory does not exist: " << outputParent << '\n';
        return 1;
    }

    const auto output = canonicalParent / outputPath.filename();
    if (fs::exists(output, error) || error) {
        std::cerr << "Output already exists or could not be checked: " << output << '\n';
        return 1;
    }
    if (isInside(source, output)) {
        std::cerr << "Output image must be outside the source directory.\n";
        return 1;
    }

    std::cout << "Creating image " << output << " from " << source << '\n';
    return runXorriso({"xorriso", "-as", "mkisofs", "-r", "-J", "-joliet-long",
                       "-o", output.string(), source.string()});
}

int burnImage(const fs::path& imagePath, const std::string& device, bool skipConfirmation) {
    if (!isRegularFile(imagePath)) {
        return 1;
    }
    if (device.empty()) {
        std::cerr << "Device must not be empty.\n";
        return 1;
    }

    if (!skipConfirmation) {
        std::cerr << "Burning writes to optical media and may be irreversible.\n"
                  << "Type 'burn' to continue: ";
        std::string response;
        if (!std::getline(std::cin, response) || response != "burn") {
            std::cerr << "Burn cancelled.\n";
            return 1;
        }
    }

    return runXorriso({"xorriso", "-as", "cdrecord", "-v", "dev=" + device,
                       "-eject", imagePath.string()});
}

} // namespace

int main(int argc, char* argv[]) {
    if (argc < 2 || std::string(argv[1]) == "--help" || std::string(argv[1]) == "-h") {
        printUsage(argv[0]);
        return argc < 2 ? 2 : 0;
    }

    const std::string command = argv[1];
    if (command == "devices" && argc == 2) {
        return runXorriso({"xorriso", "-devices"});
    }
    if (command == "image" && argc == 4) {
        return createImage(argv[2], argv[3]);
    }
    if (command == "burn" && (argc == 4 || argc == 5)) {
        const bool skipConfirmation = argc == 5 && std::string(argv[4]) == "--yes";
        if (argc == 5 && !skipConfirmation) {
            printUsage(argv[0]);
            return 2;
        }
        return burnImage(argv[2], argv[3], skipConfirmation);
    }
    if (command == "verify" && argc == 3) {
        if (!isRegularFile(argv[2])) {
            return 1;
        }
        return runXorriso({"xorriso", "-indev", argv[2], "-check_media"});
    }

    printUsage(argv[0]);
    return 2;
}
