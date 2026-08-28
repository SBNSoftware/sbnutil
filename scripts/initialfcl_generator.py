#!/usr/bin/env python3
"""
Mass FCL File Generator for SBND Productions

This script efficiently generates large numbers of FCL files with unique run/subrun combinations
by using a template approach instead of calling the sbndpoms_genfclwithrunnumber_maker script for each file.
"""

import argparse
import json
import os
import re
import sys
import time
import subprocess
import multiprocessing
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Tuple, Optional

# Configuration constants (easily adjustable)
FILES_PER_DIRECTORY = 2000
FILES_PER_BATCH = 1000
MAX_FILE_WORKERS = 4
MAX_SAM_WORKERS = 2
SUBRUNS_PER_RUN = 99

# Default values
DEFAULT_FCL = "prodgenie_corsika_proton_rockbox_lowenergydirt_sbnd.fcl"
DEFAULT_NFILES = 20
DEFAULT_MDPRODNAME = "SBND2026A"
DEFAULT_OUTDIR = "/pnfs/sbnd/scratch/sbndpro/initialfcl"
DEFAULT_MDPROJVER = "v10_06_00_05"
DEFAULT_MDPRODTYPE = "official"
DEFAULT_MDSTAGENAME = "gen"

class FCLGenerator:
    def __init__(self, args):
        self.args = args
        self.template_fcl = None
        self.template_json = None
        self.start_time = time.time()
        self.files_processed = 0
        self.current_run = args.start_run
        self.current_subrun = args.start_subrun
        
        # Setup directories
        self.work_base = Path(f"{args.mdprodname}-{args.fclname}")
        self.work_base.mkdir(exist_ok=True)
        
        # Setup logging
        log_file = self.work_base / f"generation_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
        self.setup_logging(log_file)
        
        self.log("═" * 60)
        self.log("FCL GENERATION STARTED")
        self.log("═" * 60)
        self.log(f"FCL: {args.fcl}")
        self.log(f"FCL Name: {args.fclname}")
        self.log(f"Production: {args.mdprodname}")
        self.log(f"Version: {args.mdprojver}")
        self.log(f"Files to generate: {args.nfiles}")
        self.log(f"Output Directory: {args.outdir}")
        self.log("─" * 60)
        
    def setup_logging(self, log_file):
        """Setup logging to both console and file"""
        import logging
        self.logger = logging.getLogger('FCLGenerator')
        
        # Set level based on verbose flag
        if self.args.verbose:
            self.logger.setLevel(logging.DEBUG)
        else:
            self.logger.setLevel(logging.INFO)
        
        # File handler
        fh = logging.FileHandler(log_file)
        fh.setLevel(logging.DEBUG)  # Always debug to file
        
        # Console handler
        ch = logging.StreamHandler()
        if self.args.verbose:
            ch.setLevel(logging.DEBUG)
        else:
            ch.setLevel(logging.INFO)
        
        formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
        fh.setFormatter(formatter)
        ch.setFormatter(formatter)
        
        self.logger.addHandler(fh)
        self.logger.addHandler(ch)
        
    def log(self, message, level='info'):
        """Log a message at specified level"""
        if level == 'debug':
            self.logger.debug(message)
        elif level == 'warning':
            self.logger.warning(message)
        elif level == 'error':
            self.logger.error(message)
        else:
            self.logger.info(message)
            
    def log_error(self, title, details=None, suggestion=None):
        """Format error messages in a clean, user-friendly way"""
        self.log("✗" * 60, 'error')
        self.log(f"ERROR: {title}", 'error')
        if details:
            self.log(f"DETAILS: {details}", 'error')
        if suggestion:
            self.log(f"SUGGESTION: {suggestion}", 'error')
        self.log("✗" * 60, 'error')
            
    def check_output_directory(self):
        """Check if output directory is writable"""
        outdir_path = Path(self.args.outdir)
        try:
            outdir_path.mkdir(parents=True, exist_ok=True)
            # Test write permission
            test_file = outdir_path / ".write_test"
            test_file.touch()
            test_file.unlink()
            self.log(f"✓ Output directory is writable: {outdir_path}")
            return True
        except Exception as e:
            self.log_error(
                "Cannot write to output directory",
                f"{outdir_path}: {e}",
                "Check permissions or specify a different --outdir"
            )
            return False
    
    def find_json_file(self, fcl_file: Path, workdir: Path) -> Optional[Path]:
        """Find the corresponding JSON file for an FCL file"""
        # Extract the base name without UUID
        base_name = fcl_file.stem
        # Remove the UUID part (everything after the last dash)
        if '-' in base_name:
            base_without_uuid = '-'.join(base_name.split('-')[:-1])
        else:
            base_without_uuid = base_name
            
        # Look for JSON files in the workdir that match the base name
        json_pattern = f"{base_without_uuid}*.json"
        json_files = list(workdir.glob(json_pattern))
        
        if not json_files:
            self.log(f"DEBUG: No JSON files found matching pattern: {json_pattern}", 'debug')
            self.log(f"DEBUG: Workdir contents: {list(workdir.glob('*.json'))}", 'debug')
            return None
            
        if len(json_files) > 1:
            self.log(f"DEBUG: Multiple JSON files found: {json_files}", 'debug')
            # Try to find the one with the same UUID
            fcl_uuid = base_name.split('-')[-1] if '-' in base_name else None
            if fcl_uuid:
                for json_file in json_files:
                    if fcl_uuid in json_file.stem:
                        return json_file
        
        # Return the first one found (or the only one)
        return json_files[0]
    
    def generate_template(self) -> Tuple[Path, Path]:
        """Generate template FCL and JSON files using the sbndpoms_genfclwithrunnumber_maker script"""
        self.log("Generating template files using sbndpoms_genfclwithrunnumber_maker script...")
        
        # Build the command to generate template
        cmd = [
            "sbndpoms_genfclwithrunnumber_maker.sh",
            "--fcl", self.args.fcl,
            "--outdir", str(self.work_base / "template"),
            "--nfiles", "1",
            "--workdir", str(self.work_base / "template_work"),
            "--mdprojver", self.args.mdprojver,
            "--mdprodname", self.args.mdprodname,
            "--mdprodtype", self.args.mdprodtype,
            "--mdstagename", self.args.mdstagename
        ]
        
        self.log(f"Running: {' '.join(cmd)}", 'debug')
        
        try:
            result = subprocess.run(cmd, check=True, capture_output=True, text=True)
            self.log("Template generation command completed", 'debug')
            if self.args.verbose:
                self.log(f"STDOUT: {result.stdout}", 'debug')
                self.log(f"STDERR: {result.stderr}", 'debug')
        except subprocess.CalledProcessError as e:
            # Extract the most relevant error information
            error_lines = []
            for line in e.stderr.split('\n'):
                if any(keyword in line.lower() for keyword in ['error', 'failed', 'exception', 'can\'t find', 'not found']):
                    error_lines.append(line.strip())
            
            if not error_lines:  # If no obvious error lines, take first non-empty line
                for line in e.stderr.split('\n'):
                    if line.strip():
                        error_lines.append(line.strip())
                        break
            
            primary_error = error_lines[0] if error_lines else "Unknown error"
            
            self.log_error(
                "Template generation failed",
                f"The sbndpoms_genfclwithrunnumber_maker script reported: {primary_error}",
                "Check that the FCL file exists and is accessible in your current environment"
            )
            
            if self.args.verbose:
                self.log("Full error output for debugging:", 'error')
                self.log(f"Exit code: {e.returncode}", 'error')
                self.log(f"STDERR:\n{e.stderr}", 'error')
                self.log(f"STDOUT:\n{e.stdout}", 'error')
            else:
                self.log("Run with --verbose to see full error details", 'error')
            
            sys.exit(1)
            
        # Find the generated template files
        template_dir = self.work_base / "template" / self.args.mdprodtype / self.args.mdprodname / self.args.mdprojver / self.args.fclname
        workdir = self.work_base / "template_work"
        
        if not template_dir.exists():
            self.log_error(
                "Template directory not found",
                f"Expected: {template_dir}",
                "The sbndpoms_genfclwithrunnumber_maker script may have failed to create output files"
            )
            sys.exit(1)
            
        # Look for the template FCL files
        fcl_files = list(template_dir.glob("*.fcl"))
        if not fcl_files:
            self.log_error(
                "No FCL files found in template directory",
                f"Directory: {template_dir}",
                "Check if the sbndpoms_genfclwithrunnumber_maker script completed successfully"
            )
            sys.exit(1)
            
        template_fcl = fcl_files[0]
        self.log(f"✓ Template FCL found: {template_fcl}")
        
        # Look for the JSON file in the workdir
        template_json = self.find_json_file(template_fcl, workdir)
        
        if not template_json or not template_json.exists():
            self.log_error(
                "JSON metadata file not found for template",
                f"FCL file: {template_fcl}\nWorkdir: {workdir}\nExpected JSON pattern: {template_fcl.stem.split('-')[0]}*.json",
                "The JSON file should be in the workdir, not the output directory"
            )
            self.log(f"Workdir contents: {list(workdir.glob('*'))}", 'debug')
            sys.exit(1)
            
        self.log(f"✓ Template JSON found: {template_json}")
        
        return template_fcl, template_json
    
    def load_template(self) -> None:
        """Load template files"""
        if self.args.template_fcl and self.args.template_json:
            template_fcl = Path(self.args.template_fcl)
            template_json = Path(self.args.template_json)
            
            if not template_fcl.exists():
                self.log_error(
                    "Provided template FCL file not found",
                    f"Path: {template_fcl}",
                    "Check the file path and permissions"
                )
                sys.exit(1)
            if not template_json.exists():
                self.log_error(
                    "Provided template JSON file not found", 
                    f"Path: {template_json}",
                    "Check the file path and permissions"
                )
                sys.exit(1)
                
            self.log("Using provided template files")
        else:
            self.log("Generating new templates...")
            template_fcl, template_json = self.generate_template()
        
        # Read template contents
        try:
            with open(template_fcl, 'r') as f:
                self.template_fcl = f.read()
                
            with open(template_json, 'r') as f:
                self.template_json = json.load(f)
                
            self.log("✓ Templates loaded successfully")
            if self.args.verbose:
                self.log(f"Template FCL preview: {self.template_fcl[:200]}...", 'debug')
                self.log(f"Template JSON keys: {list(self.template_json.keys())}", 'debug')
        except Exception as e:
            self.log_error(
                "Failed to load template files",
                f"Error: {e}",
                "Check that the template files are valid and accessible"
            )
            sys.exit(1)
    
    def calculate_directory(self, file_index: int) -> Path:
        """Calculate which directory should contain this file"""
        dir_index = file_index // FILES_PER_DIRECTORY
        return Path(self.args.outdir) / f"part_{dir_index:04d}"
    
    def generate_single_file(self, run: int, subrun: int, file_index: int) -> Dict:
        """Generate a single FCL file and its JSON metadata"""
        # Generate file name according to new pattern
        base_name = f"{self.args.mdprodname}_{self.args.fclname}_{self.args.mdprojver}_run{run}_subrun{subrun}"
        fcl_filename = f"{base_name}.fcl"
        json_filename = f"{base_name}.json"
        
        # Calculate output directory
        output_dir = self.calculate_directory(file_index)
        output_dir.mkdir(parents=True, exist_ok=True)
        
        fcl_path = output_dir / fcl_filename
        json_path = output_dir / json_filename
        
        # Generate FCL content
        fcl_content = self.template_fcl
        fcl_content = re.sub(r'source\.firstRun:\s*\d+', f'source.firstRun: {run}', fcl_content)
        fcl_content = re.sub(r'source\.firstSubRun:\s*\d+', f'source.firstSubRun: {subrun}', fcl_content)
        
        # Generate JSON content
        json_content = self.template_json.copy()
        json_content['file_name'] = fcl_filename
        json_content['fcl.name'] = fcl_filename
        json_content['runs'] = [[run, subrun, "physics"]]
        json_content['production.name'] = self.args.mdprodname
        json_content['production.type'] = self.args.mdprodtype
        json_content['sbnd_project.version'] = self.args.mdprojver
        json_content['sbnd_project.name'] = self.args.fclname
        json_content['start_time'] = datetime.now().isoformat()
        json_content['end_time'] = datetime.now().isoformat()
        
        # Write files
        with open(fcl_path, 'w') as f:
            f.write(fcl_content)
            
        with open(json_path, 'w') as f:
            json.dump(json_content, f, indent=2)
        
        return {
            'fcl_path': str(fcl_path),
            'json_path': str(json_path),
            'fcl_filename': fcl_filename,
            'run': run,
            'subrun': subrun,
            'file_index': file_index
        }
    
    def declare_to_sam(self, file_info: Dict) -> bool:
        """Declare a single file to SAM"""
        if self.args.test:
            return True
            
        try:
            # Declare file
            declare_sbnd_cmd = [
                'samweb', '-e', 'sbnd', 'declare-file', file_info['json_path']
            ]
            result = subprocess.run(declare_sbnd_cmd, check=True, capture_output=True, text=True)
            if self.args.verbose:
                self.log(f"SAM declare output SBND: {result.stdout}", 'debug')
            declare_sbn_cmd = [
                'samweb', '-e', 'sbn', 'declare-file', file_info['json_path']
            ]
            result = subprocess.run(declare_sbn_cmd, check=True, capture_output=True, text=True)
            if self.args.verbose:
                self.log(f"SAM declare output SBN: {result.stdout}", 'debug')
            
            # Add file location
            location_sbnd_cmd = [
                'samweb', '-e', 'sbnd', 'add-file-location',
                file_info['fcl_filename'], f"dcache:{Path(file_info['fcl_path']).parent}"
            ]
            result = subprocess.run(location_sbnd_cmd, check=True, capture_output=True, text=True)
            if self.args.verbose:
                self.log(f"SAM location output SBND: {result.stdout}", 'debug')
            location_sbn_cmd = [
                'samweb', '-e', 'sbn', 'add-file-location',
                file_info['fcl_filename'], f"dcache:{Path(file_info['fcl_path']).parent}"
            ]
            result = subprocess.run(location_sbn_cmd, check=True, capture_output=True, text=True)
            if self.args.verbose:
                self.log(f"SAM location output SBN: {result.stdout}", 'debug')
            
            return True
        except subprocess.CalledProcessError as e:
            self.log_error(
                f"SAM declaration failed for {file_info['fcl_filename']}",
                f"Error: {e.stderr.strip() if e.stderr else 'Unknown error'}"
            )
            return False
    
    def create_sam_dataset(self) -> bool:
        """Create the SAM dataset definition"""
        if self.args.test:
            self.log("TEST MODE: Would create SAM dataset")
            return True
            
        dataset_name = f"{self.args.mdprodtype}_{self.args.mdprodname}_{self.args.fclname}_{self.args.mdprojver}_initialfcl_sbnd"
        
        # Pattern to match our generated files
        file_pattern = f"{self.args.mdprodname}_{self.args.fclname}_{self.args.mdprojver}_run%.fcl"
        
        try:
            # Check if dataset already exists
            check_sbnd_cmd = ['samweb', '-e', 'sbnd', 'list-definitions', dataset_name]
            result = subprocess.run(check_sbnd_cmd, capture_output=True, text=True)
            check_sbn_cmd = ['samweb', '-e', 'sbn', 'list-definitions', dataset_name]
            result = subprocess.run(check_sbn_cmd, capture_output=True, text=True)
            
            if result.returncode == 0 and dataset_name in result.stdout:
                self.log(f"Dataset {dataset_name} already exists, skipping creation")
                return True
            
            # Create new dataset
            create_sbnd_cmd = [
                'samweb', '-e', 'sbnd', 'create-definition', dataset_name,
                f"file_name like {file_pattern} and production.name {self.args.mdprodname} and production.type {self.args.mdprodtype}"
            ]
            result = subprocess.run(create_sbnd_cmd, check=True, capture_output=True, text=True)
            self.log(f"✓ Created SAM dataset in SBND: {dataset_name}")
            create_sbn_cmd = [
                'samweb', '-e', 'sbn', 'create-definition', dataset_name,
                f"file_name like {file_pattern} and production.name {self.args.mdprodname} and production.type {self.args.mdprodtype}"
            ]
            result = subprocess.run(create_sbn_cmd, check=True, capture_output=True, text=True)
            self.log(f"✓ Created SAM dataset in SBN: {dataset_name}")

            if self.args.verbose:
                self.log(f"Dataset creation output: {result.stdout}", 'debug')
            return True
        except subprocess.CalledProcessError as e:
            self.log_error(
                "Failed to create SAM dataset",
                f"Error: {e.stderr.strip() if e.stderr else 'Unknown error'}"
            )
            return False
    
    def update_progress(self, current: int, total: int, operation: str):
        """Update progress display"""
        percent = (current / total) * 100
        elapsed = time.time() - self.start_time
        if current > 0:
            eta = (elapsed / current) * (total - current)
        else:
            eta = 0
            
        self.log(f"📊 {operation}: {current}/{total} ({percent:.1f}%) - Elapsed: {elapsed:.1f}s - ETA: {eta:.1f}s")
    
    def run(self):
        """Main execution function"""
        self.log("Starting FCL generation process...")
        
        # Check output directory first
        if not self.check_output_directory():
            sys.exit(1)
        
        # Load templates
        self.load_template()
        
        # Calculate total needed files from starting point
        total_needed = self.args.nfiles
        start_index = 0  # File index counter
        
        self.log(f"Generating {total_needed} files starting from run {self.current_run}.{self.current_subrun}")
        
        # Generate files in batches
        all_file_info = []
        batch_num = 0
        
        while start_index < total_needed:
            batch_size = min(FILES_PER_BATCH, total_needed - start_index)
            batch_files = batch_size
            
            self.log(f"Processing batch {batch_num + 1} ({batch_files} files)...")
            
            # Generate files in parallel
            with ProcessPoolExecutor(max_workers=MAX_FILE_WORKERS) as executor:
                futures = []
                
                for i in range(batch_files):
                    file_index = start_index + i
                    futures.append(
                        executor.submit(
                            self.generate_single_file, 
                            self.current_run, 
                            self.current_subrun,
                            file_index
                        )
                    )
                    
                    # Update run/subrun for next file
                    self.current_subrun += 1
                    if self.current_subrun > SUBRUNS_PER_RUN:
                        self.current_subrun = 1
                        self.current_run += 1
                
                # Collect results
                for future in as_completed(futures):
                    try:
                        file_info = future.result()
                        all_file_info.append(file_info)
                    except Exception as e:
                        self.log_error(
                            "File generation failed",
                            f"Error: {e}",
                            "Check available disk space and permissions"
                        )
                        if not self.args.continue_on_error:
                            sys.exit(1)
            
            start_index += batch_files
            batch_num += 1
            
            # Update progress every 10% or at batch boundaries
            if start_index % max(1, total_needed // 10) == 0 or start_index == total_needed:
                self.update_progress(start_index, total_needed, "File generation")
        
        self.log("✓ File generation completed successfully")
        
        # SAM declaration phase
        if not self.args.test:
            self.log("Starting SAM declaration...")
            
            # Create dataset on first declaration
            if not self.create_sam_dataset():
                if not self.args.continue_on_error:
                    sys.exit(1)
            
            # Declare files in parallel
            declared_count = 0
            with ProcessPoolExecutor(max_workers=MAX_SAM_WORKERS) as executor:
                futures = {executor.submit(self.declare_to_sam, info): info for info in all_file_info}
                
                for future in as_completed(futures):
                    file_info = futures[future]
                    try:
                        success = future.result()
                        if success:
                            declared_count += 1
                        elif not self.args.continue_on_error:
                            self.log_error(
                                "SAM declaration failed",
                                "continue_on_error is False - stopping execution"
                            )
                            sys.exit(1)
                    except Exception as e:
                        self.log_error(
                            f"SAM declaration failed for {file_info['fcl_filename']}",
                            f"Error: {e}"
                        )
                        if not self.args.continue_on_error:
                            sys.exit(1)
                    
                    # Update progress every 10%
                    if declared_count % max(1, total_needed // 10) == 0 or declared_count == total_needed:
                        self.update_progress(declared_count, total_needed, "SAM declaration")
            
            self.log(f"✓ SAM declaration completed: {declared_count}/{total_needed} files declared")
        
        # Final summary
        total_time = time.time() - self.start_time
        self.log("═" * 60)
        self.log("PROCESS COMPLETED SUCCESSFULLY")
        self.log("═" * 60)
        self.log(f"Total time: {total_time:.2f} seconds")
        self.log(f"Files generated: {len(all_file_info)}")
        self.log(f"Final run/subrun: {self.current_run}.{self.current_subrun}")
        
        if not self.args.test:
            self.log(f"SAM dataset: {self.args.mdprodtype}_{self.args.mdprodname}_{self.args.fclname}_{self.args.mdprojver}_initialfcl_sbnd")

def main():
    parser = argparse.ArgumentParser(
        description="Mass FCL File Generator for SBND Productions",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter
    )
    
    # Required arguments (with defaults)
    parser.add_argument('--fcl', 
                       default=DEFAULT_FCL, 
                       help='Input FCL file name')
    
    # FCLNAME will be derived from FCL by default
    parser.add_argument('--fclname', 
                       help='FCL name for metadata (default: FCL without .fcl extension)')
    
    parser.add_argument('--nfiles', 
                       type=int, 
                       default=DEFAULT_NFILES,
                       help='Number of files to generate')
    
    parser.add_argument('--mdprodname', 
                       default=DEFAULT_MDPRODNAME,
                       help='Production name')
    
    parser.add_argument('--outdir', 
                       default=DEFAULT_OUTDIR,
                       help='Output directory')
    
    parser.add_argument('--mdprojver', 
                       default=DEFAULT_MDPROJVER,
                       help='Project version')
    
    parser.add_argument('--mdprodtype', 
                       default=DEFAULT_MDPRODTYPE,
                       help='Production type')
    
    parser.add_argument('--mdstagename', 
                       default=DEFAULT_MDSTAGENAME,
                       help='Stage name')
    
    # Optional arguments
    parser.add_argument('--template-fcl', 
                       help='Template FCL file (optional, will generate if not provided)')
    
    parser.add_argument('--template-json', 
                       help='Template JSON file (optional, will generate if not provided)')
    
    parser.add_argument('--start-run', 
                       type=int, 
                       default=1, 
                       help='Starting run number')
    
    parser.add_argument('--start-subrun', 
                       type=int, 
                       default=1, 
                       help='Starting subrun number')
    
    parser.add_argument('--test', 
                       action='store_true', 
                       help='Test mode (generate 5 files, no SAM ops)')
    
    parser.add_argument('--continue-on-error', 
                       action='store_true', 
                       help='Continue processing even if errors occur')
    
    parser.add_argument('--verbose', 
                       action='store_true', 
                       help='Enable verbose logging')
    
    args = parser.parse_args()
    
    # Derive FCLNAME from FCL if not provided
    if args.fclname is None:
        args.fclname = Path(args.fcl).stem  # Remove .fcl extension
        print(f"Using derived FCLNAME: {args.fclname}")
    
    # Override for test mode
    if args.test:
        args.nfiles = 5
        print("TEST MODE: Generating 5 files only, no SAM operations")
    
    # Validate arguments
    if args.start_subrun < 1 or args.start_subrun > SUBRUNS_PER_RUN:
        print(f"ERROR: start-subrun must be between 1 and {SUBRUNS_PER_RUN}")
        sys.exit(1)
    
    generator = FCLGenerator(args)
    generator.run()

if __name__ == "__main__":
    main()
