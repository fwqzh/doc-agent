"""Static contract tests for the native Windows deployment entrypoint."""

import json
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]


class WindowsNativeDeployContractTest(unittest.TestCase):
    def test_entrypoint_uses_native_processes_and_speed_mode(self):
        script = (REPO_ROOT / "deploy-windows-native.ps1").read_text(encoding="utf-8")
        environment = (
            REPO_ROOT / "deploy" / "windows-native" / ".env.example"
        ).read_text(encoding="utf-8")

        self.assertIn('ValidateSet("Deploy", "Setup", "Start", "Stop", "Restart", "Status", "Doctor")', script)
        self.assertIn('Start-NativeProcess -Name "web"', script)
        self.assertIn('File = "backend\\config_service.py"', script)
        self.assertIn('File = "backend\\runtime_service.py"', script)
        self.assertIn('File = "backend\\mcp_service.py"', script)
        self.assertIn('File = "backend\\data_process_service.py"', script)
        self.assertIn('Test-Path (Join-Path $frontendDirectory "pnpm-lock.yaml")', script)
        self.assertNotIn("docker compose", script.lower())
        self.assertNotIn("wsl.exe", script.lower())
        self.assertIn("DEPLOYMENT_VERSION=speed", environment)
        self.assertIn("DOCKER_ENVIRONMENT=false", environment)

    def test_document_processing_is_on_by_default_and_can_be_disabled(self):
        script = (REPO_ROOT / "deploy-windows-native.ps1").read_text(encoding="utf-8")

        self.assertIn("[switch]$WithoutDataProcess", script)
        self.assertGreaterEqual(script.count("if (-not $WithoutDataProcess)"), 2)
        self.assertIn('$uvArguments += @("--extra", "data-process")', script)

    def test_runtime_paths_are_generated_for_windows(self):
        script = (REPO_ROOT / "deploy-windows-native.ps1").read_text(encoding="utf-8")
        required_keys = (
            "ROOT_DIR",
            "LOG_DIR",
            "SKILLS_PATH",
            "OFFICIAL_SKILLS_ZIP_PATH",
            "MEMORY_PROVIDER_PLUGINS_DIR",
            "AGENT_WORKSPACE_ROOT",
            "ALLOWED_SKILL_UPLOAD_ROOT",
            "UPLOAD_FOLDER",
            "LIBREOFFICE_PROFILE_DIR",
            "RAY_TEMP_DIR",
        )
        for key in required_keys:
            with self.subTest(key=key):
                self.assertIn(f'-Key "{key}"', script)

    def test_frontend_start_command_is_cross_platform(self):
        package = json.loads(
            (REPO_ROOT / "frontend" / "package.json").read_text(encoding="utf-8")
        )
        self.assertEqual(
            package["scripts"]["start"],
            "cross-env NODE_ENV=production node server.js",
        )


if __name__ == "__main__":
    unittest.main()
