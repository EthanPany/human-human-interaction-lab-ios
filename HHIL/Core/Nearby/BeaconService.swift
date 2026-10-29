import CoreBluetooth
import Foundation

/// Bluetooth assist for UWB: this badge advertises a short rotating id from
/// the server (`nearby:bleId`, never the user id) and listens for other
/// badges doing the same, keeping a smoothed signal strength (RSSI) per id.
///
/// It is a coarse signal only. NearbyService uses it to know who is in the
/// area (approach cues, waking UWB sessions sooner, which peers get a UWB
/// slot) and reports it to the server, which may call two people together on
/// Bluetooth alone only when UWB had nothing for a while and the signal is
/// very strong (the badge then says it is estimated).
///
/// Runs only while the badge is worn full screen and the app is in front,
/// like UWB, so no Bluetooth background mode is needed and the radio is off
/// the rest of the time. Advertising costs little; the scan runs only while
/// the badge is worn, when the screen is on anyway.
@MainActor
final class BeaconService: NSObject {
    /// Every HHIL badge advertises this service, with its id as the local name.
    static let serviceUUID = CBUUID(string: "8E3F1C52-6A0B-4D8E-9C4B-5B7A2F0D1E63")
    /// Local name: this prefix plus the 6 character id (fits the 31 byte packet with the service).
    static let namePrefix = "H"

    struct Sighting {
        /// Smoothed dBm.
        var rssi: Double
        var lastSeen: Date
    }

    /// Heard within this long counts (a few advertising rounds).
    static let freshFor: TimeInterval = 6

    /// Smoothed signal per Bluetooth id, for ids heard recently.
    private(set) var sightings: [String: Sighting] = [:]
    /// For the debug panel.
    private(set) var statusLabel = "Off"

    private var central: CBCentralManager?
    private var peripheral: CBPeripheralManager?
    private var advertisedId: String?
    private var running = false

    /// Bluetooth permission was refused (the badge still works on UWB alone).
    var isDenied: Bool { CBManager.authorization == .denied || CBManager.authorization == .restricted }

    /// Badge worn: start listening (and advertising once there is an id).
    func start() {
        guard !running else { return }
        running = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        } else {
            scanIfReady()
        }
        if peripheral == nil {
            peripheral = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionShowPowerAlertKey: false])
        } else {
            advertiseIfReady()
        }
    }

    /// Badge taken off: radio quiet.
    func stop() {
        guard running else { return }
        running = false
        central?.stopScan()
        peripheral?.stopAdvertising()
        sightings.removeAll()
        statusLabel = "Off"
    }

    /// The id to advertise (a new one every 15 minutes).
    func advertise(id: String?) {
        guard id != advertisedId else { return }
        advertisedId = id
        peripheral?.stopAdvertising()
        advertiseIfReady()
    }

    /// Smoothed signal for an id heard recently (nil when not heard).
    func rssi(for bleId: String, now: Date = Date()) -> Double? {
        guard let s = sightings[bleId], now.timeIntervalSince(s.lastSeen) < Self.freshFor else { return nil }
        return s.rssi
    }

    /// Fresh sightings, strongest first (what goes to the server).
    func freshSightings(limit: Int, now: Date = Date()) -> [BleSighting] {
        sightings
            .filter { now.timeIntervalSince($0.value.lastSeen) < 4 }
            .sorted { $0.value.rssi > $1.value.rssi }
            .prefix(limit)
            .map { BleSighting(bleId: $0.key, rssi: ($0.value.rssi * 10).rounded() / 10) }
    }

    private func scanIfReady() {
        guard running, let central, central.state == .poweredOn else { return }
        // Duplicates on: every advertisement updates the signal (foreground only, like the badge).
        central.scanForPeripherals(withServices: [Self.serviceUUID],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        updateStatus()
    }

    private func advertiseIfReady() {
        guard running, let peripheral, peripheral.state == .poweredOn, let id = advertisedId else { updateStatus(); return }
        if peripheral.isAdvertising { peripheral.stopAdvertising() }
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID],
            CBAdvertisementDataLocalNameKey: Self.namePrefix + id,
        ])
        updateStatus()
    }

    private func updateStatus() {
        if isDenied { statusLabel = "Bluetooth is off for this app (UWB only)"; return }
        guard running else { statusLabel = "Off"; return }
        let scanning = central?.state == .poweredOn
        let advertising = peripheral?.state == .poweredOn && advertisedId != nil
        switch (scanning, advertising) {
        case (true, true): statusLabel = "Listening and advertising \(advertisedId ?? "")"
        case (true, false): statusLabel = advertisedId == nil ? "Listening (no id from the server)" : "Listening"
        case (false, _): statusLabel = central?.state == .poweredOff ? "Bluetooth is turned off" : "Starting"
        }
    }

    fileprivate func heard(name: String, rssi: Double) {
        guard name.hasPrefix(Self.namePrefix), name.count == Self.namePrefix.count + 6 else { return }
        // 127 means "not available"; anything weaker than -100 is noise
        guard rssi < 0, rssi > -100 else { return }
        let id = String(name.dropFirst(Self.namePrefix.count)).uppercased()
        let now = Date()
        if var s = sightings[id], now.timeIntervalSince(s.lastSeen) < Self.freshFor {
            // Bodies and turns swing RSSI by 10 dB: smooth, a little quicker to rise than to fall
            let k = rssi > s.rssi ? 0.35 : 0.2
            s.rssi += (rssi - s.rssi) * k
            s.lastSeen = now
            sightings[id] = s
        } else {
            sightings[id] = Sighting(rssi: rssi, lastSeen: now)
        }
        // Forget ids not heard for a while (rotated, or gone)
        if sightings.count > 64 {
            sightings = sightings.filter { now.timeIntervalSince($0.value.lastSeen) < Self.freshFor }
        }
    }

    fileprivate func stateChanged() {
        scanIfReady()
        advertiseIfReady()
        updateStatus()
    }
}

extension BeaconService: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated { self.stateChanged() }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String else { return }
        let value = RSSI.doubleValue
        MainActor.assumeIsolated { self.heard(name: name, rssi: value) }
    }
}

extension BeaconService: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        MainActor.assumeIsolated { self.stateChanged() }
    }
}
