from __future__ import annotations

from datetime import date, datetime
from pathlib import Path
import shutil


class BackupManager:
    def __init__(self, root_dir: str):
        self.root = Path(root_dir)
        self.local_dir = self.root / "local"
        self.cloud_dir = self.root / "cloud_mock"
        self.state_file = self.root / ".last_backup_date"
        self.local_dir.mkdir(parents=True, exist_ok=True)
        self.cloud_dir.mkdir(parents=True, exist_ok=True)

    def _already_backed_up_today(self) -> bool:
        if not self.state_file.exists():
            return False
        return self.state_file.read_text(encoding="utf-8").strip() == date.today().isoformat()

    def _mark_backup_done(self) -> None:
        self.state_file.write_text(date.today().isoformat(), encoding="utf-8")

    def daily_backup(self, file_path: str) -> None:
        if self._already_backed_up_today():
            return

        source = Path(file_path)
        if not source.exists():
            return

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        local_target = self.local_dir / f"pos_data_{timestamp}.db"
        cloud_target = self.cloud_dir / f"pos_data_{timestamp}.db"

        shutil.copy2(source, local_target)
        shutil.copy2(source, cloud_target)
        self._mark_backup_done()
