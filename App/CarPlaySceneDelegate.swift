import CarPlay
import CoreLocation
import MapKit
import Nav2PilotKit
import UIKit

/// The CarPlay screen, a "driving task" app: CarPlay draws Apple's templates, the app only fills them.
///
/// - Destinations: the favorites on Apple Maps (point of interest template), nearest first. A place's card
///   sends it to the selected car. CarPlay gives driving task apps no map of their own and no search.
/// - Car: the cars with their status, the one to send to, clearing its destination.
///
/// Setup stays on the iPhone; without it the screen only says what is missing. The templates are updated in
/// place, so a new status does not move the driver to another tab.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPPointOfInterestTemplateDelegate {
    private var interfaceController: CPInterfaceController?
    private var model: CarScreenModel?
    private let location = CoreLocationProvider()
    private var position: LatLng?
    private var statuses: [String: String] = [:]
    private var defaultsObserver: NSObjectProtocol?

    private var setupTemplate: CPListTemplate?
    private var tabBar: CPTabBarTemplate?
    private var placesTemplate: CPPointOfInterestTemplate?
    private var noPlacesTemplate: CPListTemplate?
    private var carsTemplate: CPListTemplate?
    /// What the places and the car list were last built from: unchanged data is not sent to CarPlay again.
    private var placesKey = ""
    private var carsKey = ""

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        model = AppContainer.makeCarScreenModel()
        // the app and the share extension write devices and favorites to the same App Group
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        refresh()
        Task {
            await refreshPosition()
            await refreshStatuses()
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        if let observer = defaultsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        defaultsObserver = nil
        self.interfaceController = nil
        model = nil
        setupTemplate = nil
        tabBar = nil
        placesTemplate = nil
        noPlacesTemplate = nil
        carsTemplate = nil
        placesKey = ""
        carsKey = ""
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        refresh()
    }

    // MARK: - templates

    private func refresh() {
        guard let model = model, let interfaceController = interfaceController else {
            return
        }
        model.reload()

        if let missing = model.setupMessage() {
            showSetup(missing, on: interfaceController)
            return
        }
        setupTemplate = nil

        let destinations = updatePlaces(model)
        let cars = updateCars(model)
        if let tabs = tabBar {
            if tabs.templates.first !== destinations {
                tabs.updateTemplates([destinations, cars])
            }
            return
        }
        let tabs = CPTabBarTemplate(templates: [destinations, cars])
        tabBar = tabs
        interfaceController.setRootTemplate(tabs, animated: false, completion: nil)
    }

    private func showSetup(_ missing: String, on interfaceController: CPInterfaceController) {
        tabBar = nil
        placesTemplate = nil
        noPlacesTemplate = nil
        carsTemplate = nil
        placesKey = ""
        carsKey = ""
        if let shown = setupTemplate {
            shown.emptyViewTitleVariants = [missing]
            return
        }
        let template = CPListTemplate(title: "Nav2Pilot", sections: [])
        template.emptyViewTitleVariants = [missing]
        template.emptyViewSubtitleVariants = ["Nav2Pilot sends destinations to your comma device."]
        setupTemplate = template
        interfaceController.setRootTemplate(template, animated: false, completion: nil)
    }

    /// The favorites on the map, or a list that says there are none (a map without places says nothing).
    private func updatePlaces(_ model: CarScreenModel) -> CPTemplate {
        let places = CarScreenModel.nearestFirst(model.favorites, from: position, limit: CarScreenModel.maximumPlaces)
        if places.isEmpty {
            placesKey = ""
            if let shown = noPlacesTemplate {
                return shown
            }
            let template = CPListTemplate(title: "Destinations", sections: [])
            template.emptyViewTitleVariants = ["No favorites yet"]
            template.emptyViewSubtitleVariants = ["Favorites saved in Nav2Pilot show up here."]
            template.tabTitle = "Destinations"
            template.tabImage = UIImage(systemName: "star.fill")
            noPlacesTemplate = template
            return template
        }
        noPlacesTemplate = nil

        var carName = "the car"
        var key = ""
        if let device = model.selectedDevice() {
            carName = device.displayName()
            key = device.dongleId
        }
        for favorite in places {
            key += "|" + favorite.id
        }
        if let here = position {
            key += String(format: "|%.3f,%.3f", here.latitude, here.longitude)
        }
        if let shown = placesTemplate, key == placesKey {
            return shown
        }
        placesKey = key

        var points: [CPPointOfInterest] = []
        for favorite in places {
            points.append(point(favorite, carName: carName))
        }
        if let shown = placesTemplate {
            shown.setPointsOfInterest(points, selectedIndex: NSNotFound)
            return shown
        }
        let template = CPPointOfInterestTemplate(title: "Destinations", pointsOfInterest: points, selectedIndex: NSNotFound)
        template.pointOfInterestDelegate = self
        template.tabTitle = "Destinations"
        template.tabImage = UIImage(systemName: "star.fill")
        placesTemplate = template
        return template
    }

    private func point(_ favorite: Favorite, carName: String) -> CPPointOfInterest {
        let destination = favorite.destination
        let coordinate = CLLocationCoordinate2D(latitude: destination.latitude, longitude: destination.longitude)
        var subtitle = destination.details
        if let here = position {
            let distance = RouteFormatting.distance(CarScreenModel.distanceMeters(favorite, from: here))
            if subtitle.isEmpty {
                subtitle = distance
            } else {
                subtitle = distance + " · " + subtitle
            }
        }
        let point = CPPointOfInterest(
            location: MKMapItem(placemark: MKPlacemark(coordinate: coordinate)),
            title: destination.displayName(),
            subtitle: subtitle,
            summary: nil,
            detailTitle: destination.displayName(),
            detailSubtitle: subtitle,
            detailSummary: "The car picks its own route.",
            pinImage: nil
        )
        point.primaryButton = CPTextButton(title: "Send to \(carName)", textStyle: .confirm) { [weak self] _ in
            self?.send(destination)
        }
        return point
    }

    private func updateCars(_ model: CarScreenModel) -> CPTemplate {
        let selected = model.selectedDevice()
        var key = selected?.dongleId ?? ""
        for device in model.devices {
            key += "|" + device.dongleId + "=" + device.displayName() + "=" + (statuses[device.dongleId] ?? "")
        }
        if let shown = carsTemplate, key == carsKey {
            return shown
        }
        carsKey = key

        var cars: [CPListItem] = []
        for device in model.devices {
            var detail: [String] = []
            if device.dongleId == selected?.dongleId {
                detail.append("Selected")
            }
            detail.append(statuses[device.dongleId] ?? "Checking…")
            let item = CPListItem(text: device.displayName(), detailText: detail.joined(separator: " · "))
            let dongleId = device.dongleId
            item.handler = { [weak self] _, completion in
                self?.model?.select(dongleId)
                self?.refresh()
                completion()
            }
            cars.append(item)
        }
        var sections = [CPListSection(items: cars, header: "Send to", sectionIndexTitle: nil)]
        if let car = selected {
            let clear = CPListItem(text: "Clear the destination", detailText: "On " + car.displayName())
            clear.handler = { [weak self] _, completion in
                self?.clearDestination()
                completion()
            }
            sections.append(CPListSection(items: [clear], header: "Destination", sectionIndexTitle: nil))
        }
        if let shown = carsTemplate {
            shown.updateSections(sections)
            return shown
        }
        let template = CPListTemplate(title: "Car", sections: sections)
        template.tabTitle = "Car"
        template.tabImage = UIImage(systemName: "car.fill")
        carsTemplate = template
        return template
    }

    // MARK: - actions

    private func send(_ destination: Destination) {
        guard let model = model else {
            return
        }
        Task {
            let outcome = await model.send(destination)
            showOutcome(outcome)
        }
    }

    private func clearDestination() {
        guard let model = model else {
            return
        }
        Task {
            let outcome = await model.clearDestination()
            showOutcome(outcome)
        }
    }

    private func showOutcome(_ outcome: SendOutcome) {
        guard let interfaceController = interfaceController else {
            return
        }
        var title = outcome.message
        if !outcome.success {
            title = "Not sent. " + outcome.message
        }
        let ok = CPAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.interfaceController?.dismissTemplate(animated: true, completion: nil)
        }
        let alert = CPAlertTemplate(titleVariants: [title], actions: [ok])
        // one modal at a time: the answer to an earlier send goes away first
        if interfaceController.presentedTemplate != nil {
            interfaceController.dismissTemplate(animated: false) { _, _ in
                interfaceController.presentTemplate(alert, animated: true, completion: nil)
            }
            return
        }
        interfaceController.presentTemplate(alert, animated: true, completion: nil)
    }

    // MARK: - position and statuses

    /// Only with the permission already given in the app: CarPlay must not make the iPhone ask for it.
    private func refreshPosition() async {
        let status = CLLocationManager().authorizationStatus
        if status != .authorizedWhenInUse && status != .authorizedAlways {
            return
        }
        position = await location.currentLocation()
        refresh()
    }

    private func refreshStatuses() async {
        guard let model = model else {
            return
        }
        for device in model.devices {
            let text = await model.status(of: device)
            statuses[device.dongleId] = text
            refresh()
        }
    }

    // MARK: - CPPointOfInterestTemplateDelegate

    nonisolated func pointOfInterestTemplate(_ pointOfInterestTemplate: CPPointOfInterestTemplate, didChangeMapRegion region: MKCoordinateRegion) {
        // the favorites do not depend on the visible region
    }
}
