//
//  ViewController.swift
//  virtualOS
//
//  Created by Jahn Bertsch.
//  Licensed under the Apache License, see LICENSE file.
//

import Cocoa
import Virtualization
import OSLog

#if arch(arm64)

final class MainViewController: NSViewController {
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var vmNameTextField: NSTextField!
    @IBOutlet weak var parameterOutlineView: NSOutlineView!
    @IBOutlet weak var startButton: NSButton!
    @IBOutlet weak var sharedFolderButton: NSButton!
    @IBOutlet weak var deleteButton: NSButton!
    @IBOutlet weak var cpuCountLabel: NSTextField!
    @IBOutlet weak var cpuCountSlider: NSSlider!
    @IBOutlet weak var ramLabel: NSTextField!
    @IBOutlet weak var ramSlider: NSSlider!
    
    fileprivate let mainStoryBoard = NSStoryboard(name: "Main", bundle: nil)
    fileprivate let viewModel = MainViewModel()
    fileprivate var diskImageSize = 1

    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.dataSource            = viewModel.tableViewDataSource
        tableView.delegate              = self
        parameterOutlineView.dataSource = viewModel.parametersViewDataSource
        parameterOutlineView.delegate   = viewModel.parametersViewDelegate
        vmNameTextField.delegate        = viewModel.textFieldDelegate

        NotificationCenter.default.addObserver(self, selector: #selector(updateUI), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateUI), name: NSControl.textDidEndEditingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateUI), name: Constants.didChangeVMLocationNotification, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(restoreImageSelected), name: Constants.restoreImageNameSelectedNotification, object: nil)

        ramSlider.target = self
        ramSlider.action = #selector(memorySliderChanged(sender:))
        cpuCountSlider.target = self
        cpuCountSlider.action = #selector(cpuCountChanged(sender:))
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        view.window?.delegate = self
        vmNameTextField.resignFirstResponder()
        if let bookmarkURL = UserDefaults.standard.vmFilesDirectory,
           let bookmarkData = UserDefaults.standard.vmFilesDirectoryBookmarkData
        {
            _ = Bookmark.startAccess(bookmarkData: bookmarkData, for: bookmarkURL)            
        }
        self.updateUI()
    }
    
    @IBAction func startButtonPressed(_ sender: NSButton) {
        if let windowController = mainStoryBoard.instantiateController(withIdentifier: "NSWindowController") as? NSWindowController,
           let vmViewController = mainStoryBoard.instantiateController(withIdentifier: "VMViewController") as? VMViewController
        {
            vmViewController.vmBundle = viewModel.vmBundle
            vmViewController.vmParameters = viewModel.vmParameters
            windowController.showWindow(self)
            windowController.contentViewController = vmViewController
        } else {
            Logger.shared.log(level: .default, "show vm window failed")
        }
    }
    
    @IBAction func installButtonPressed(_ sender: NSButton) {
        if let windowController = mainStoryBoard.instantiateController(withIdentifier: "NSWindowController") as? NSWindowController,
           let restoreImageViewController = mainStoryBoard.instantiateController(withIdentifier: "RestoreImageViewController") as? RestoreImageViewController
        {
            windowController.showWindow(self)
            windowController.contentViewController = restoreImageViewController
            if let parentFrame = view.window?.frame,
               let childWindow = restoreImageViewController.view.window
            {
                childWindow.setFrame(parentFrame.offsetBy(dx: 200, dy: 10), display: true)
            }
        } else {
            Logger.shared.log(level: .default, "show restore image window failed")
        }
    }
    
    @IBAction func deleteButtonPressed(_ sender: Any) {
        guard let vmBundle = viewModel.vmBundle else {
            return
        }
        
        let alert: NSAlert = NSAlert.okCancelAlert(messageText: "Delete VM '\(vmBundle.name)'?", informativeText: "This can not be undone.", alertStyle: .warning)
        let selection = alert.runModal()
        if selection == NSApplication.ModalResponse.alertFirstButtonReturn ||
           selection == NSApplication.ModalResponse.OK
        {
            viewModel.deleteVM(selection: selection, vmBundle: vmBundle)
            viewModel.vmBundle = nil
            viewModel.vmParameters = nil
        }

        self.updateUI()
    }
        
    @IBAction func sharedFolderButtonPressed(_ sender: Any) {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.prompt = "Select"
        let modalResponse = openPanel.runModal()
        var sharedFolderURL: URL?
        if modalResponse == .OK,
           let selectedURL = openPanel.url
        {
            sharedFolderURL = selectedURL
        } else if modalResponse == .cancel {
            sharedFolderURL = nil
        }
        
        viewModel.set(sharedFolderUrl: sharedFolderURL)
        updateOutlineView()
    }
    
    @objc func restoreImageSelected(notification: Notification) {
        if let userInfo = notification.userInfo,
           let restoreImageName = userInfo[Constants.selectedRestoreImage] as? String
        {
            if restoreImageName != Constants.restoreImageNameLatest {
                let accessoryView = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 20))
                accessoryView.stringValue = "\(UserDefaults.standard.diskSize)"
                
                let alert = NSAlert.okCancelAlert(messageText: "Disk Image Size in GB", informativeText: "Disk size can not be changed after VM is created. Minimum disk size is 30 GB. During install, a lot of RAM is used, ignore the warning about low system memory.", accessoryView: accessoryView)
                let modalResponse = alert.runModal()
                accessoryView.becomeFirstResponder()

                if modalResponse == .OK || modalResponse == .alertFirstButtonReturn  {
                    diskImageSize = Int(accessoryView.intValue)
                } else {
                    return // cancel install
                }
                if diskImageSize < 30 {
                    self.diskImageSize = 30
                }
            }
            
            showSheet(mode: .install, restoreImageName: restoreImageName, diskImageSize: self.diskImageSize)
        }
    }
    
    @objc func cpuCountChanged(sender: NSSlider) {
        updateUIAndStoreParametersToDisk()
    }
    
    @objc func memorySliderChanged(sender: NSSlider) {
        updateUIAndStoreParametersToDisk()
    }
        
    @objc func updateUI() {
        self.tableView.reloadData()
        cpuCountSlider.isEnabled = false
        ramSlider.isEnabled = false
        
        if let selectedRow = viewModel.selectedRow,
           let vmBundle = viewModel.tableViewDataSource.vmBundle(forRow: selectedRow)
        {
            vmNameTextField.stringValue = vmBundle.name
            tableView.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
            viewModel.vmBundle = vmBundle
            if let vmParameters = VMParameters.readFrom(url: vmBundle.url) {
                viewModel.vmParameters = vmParameters
                viewModel.textFieldDelegate.vmBundle = vmBundle
                updateButtons(enabled: true)
                updateLabels(setZero: false)
                updateCpuCount(vmParameters)
                updateRam(vmParameters)
            }
        } else {
            vmNameTextField.stringValue = ""
            viewModel.selectedRow = 0
            updateButtons(enabled: false)
            updateLabels(setZero: true)
        }

        updateOutlineView()
    }
    
    func showErrorAlert(error: Error) {
        var messageText = "Error"
        var informativeText = "An unknown error occurred."
        
        if let vzError = error as? VZError,
           let reason = vzError.userInfo[NSLocalizedFailureErrorKey] as? String,
           let failureReason = vzError.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
           let underlyingError = vzError.userInfo[NSUnderlyingErrorKey] as? NSError
        {
            messageText = failureReason
            informativeText = reason + " " + underlyingError.localizedDescription + "\n\n(Error Code: \(vzError.errorCode), Underlying Error Domain: \(underlyingError.domain), Underlying Error Code: \(underlyingError.code))"
            Logger.shared.log(level: .default, "vz error: \(messageText) \(informativeText)")
        } else {
            informativeText = error.localizedDescription
            Logger.shared.log(level: .default, "error: \(error.localizedDescription)")
        }

        let alert = NSAlert.okCancelAlert(messageText: messageText, informativeText: informativeText, showCancelButton: false)
        let _ = alert.runModal()
    }
    
    // MARK: - Private

    fileprivate func updateButtons(enabled: Bool) {
        startButton.isEnabled = enabled
        sharedFolderButton.isEnabled = enabled
        deleteButton.isEnabled = enabled
        vmNameTextField.isEnabled = enabled
    }
    
    fileprivate func updateCpuCount(_ vmParameters: VMParameters) {
        cpuCountSlider.minValue = Double(vmParameters.cpuCountMin)
        cpuCountSlider.maxValue = Double(vmParameters.cpuCountMax)
        cpuCountSlider.numberOfTickMarks = Int(cpuCountSlider.maxValue - cpuCountSlider.minValue)
        cpuCountSlider.doubleValue = Double(vmParameters.cpuCount)
        cpuCountSlider.isEnabled = true
    }
    
    fileprivate func updateRam(_ vmParameters: VMParameters) {
        ramSlider.minValue = max(Double(vmParameters.memorySizeInGBMin), 2.0)
        ramSlider.maxValue = Double(vmParameters.memorySizeInGBMax)
        ramSlider.numberOfTickMarks = Int(ramSlider.maxValue - ramSlider.minValue)
        ramSlider.doubleValue = Double(vmParameters.memorySizeInGB)
        ramSlider.isEnabled = true
    }
    
    fileprivate func updateLabels(setZero: Bool) {
        let cpuCount = Int(round(cpuCountSlider.doubleValue))
        let memorySizeInGB = Int(round(ramSlider.doubleValue))
        viewModel.vmParameters?.cpuCount = cpuCount
        viewModel.vmParameters?.memorySizeInGB = UInt64(memorySizeInGB)
        
        if setZero {
            cpuCountLabel.stringValue = "CPU Count"
            ramLabel.stringValue = "RAM"
        } else {
            cpuCountLabel.stringValue = "CPU Count: \(cpuCount)"
            ramLabel.stringValue = "RAM: \(memorySizeInGB) GB"
        }
    }
    
    fileprivate func updateOutlineView() {
        parameterOutlineView.reloadData()
    }
    
    fileprivate func updateUIAndStoreParametersToDisk() {
        viewModel.storeParametersToDisk()
        updateLabels(setZero: false)
        updateOutlineView()
    }
    
    fileprivate func updateButtonEnabledState() {
        var enabled = false
        if viewModel.selectedRow != nil {
            enabled = true
        }
        vmNameTextField.isEnabled    = enabled
        startButton.isEnabled        = enabled
        sharedFolderButton.isEnabled = enabled
        deleteButton.isEnabled       = enabled
        ramSlider.isEnabled          = enabled
        cpuCountSlider.isEnabled     = enabled
    }

    fileprivate func showSheet(mode: ProgressViewController.Mode, restoreImageName: String?, diskImageSize: Int?)  {
        if let progressWindowController = mainStoryBoard.instantiateController(withIdentifier: "ProgressWindowController") as? NSWindowController,
           let progressWindow = progressWindowController.window
        {
            if let progressViewController = progressWindow.contentViewController as? ProgressViewController {
                progressViewController.mode = mode
                progressViewController.diskImageSize = diskImageSize
                progressViewController.restoreImageName = restoreImageName
                presentAsSheet(progressViewController)
            }
        } else {
            Logger.shared.log(level: .default, "show modal failed")
        }
    }
}

extension MainViewController: NSTableViewDelegate {
    func tableViewSelectionDidChange(_ notification: Notification) {
        var row: Int? = nil
        
        if let userInfo = notification.userInfo,
            let indexSet = userInfo["NSTableViewCurrentRowSelectionUserInfoKey"] as? NSIndexSet {
            if indexSet.count > 0 {
                row = indexSet.firstIndex
            }
        }
        
        if let row  = row {
            viewModel.selectedRow = row
            updateUI()
            updateButtonEnabledState()
        }
    }
}

extension MainViewController: NSWindowDelegate  {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let alert: NSAlert = NSAlert.okCancelAlert(messageText: "Quit", informativeText: "Quitting the app will stop all virtual machines.", alertStyle: .warning)
        let selection = alert.runModal()
        if selection == NSApplication.ModalResponse.alertFirstButtonReturn ||
           selection == NSApplication.ModalResponse.OK
        {
            NSApplication.shared.terminate(self)
            return true
        } else {
            return false
        }
    }
}

#else

// minimum implementation used for intel cpus

final class MainViewController: NSViewController {
    @IBOutlet weak var vmNameTextField: NSTextField!
    @IBOutlet weak var installButton: NSButton!
    @IBOutlet weak var startButton: NSButton!
    @IBOutlet weak var sharedFolderButton: NSButton!
    @IBOutlet weak var deleteButton: NSButton!
    @IBOutlet weak var cpuCountLabel: NSTextField!
    @IBOutlet weak var cpuCountSlider: NSSlider!
    @IBOutlet weak var ramLabel: NSTextField!
    @IBOutlet weak var ramSlider: NSSlider!

    override func viewWillAppear() {
        super.viewWillAppear()
        vmNameTextField.stringValue = "Virtualization requires an Apple Silicon machine"
        vmNameTextField.isEditable = false
        installButton.isEnabled = false
        startButton.isEnabled = false
        sharedFolderButton.isEnabled = false
        deleteButton.isEnabled = false
        cpuCountSlider.isEnabled = false
        ramSlider.isEnabled = false
        cpuCountLabel.stringValue = ""
        ramLabel.stringValue = ""
    }
}

#endif

// place all code before #else
