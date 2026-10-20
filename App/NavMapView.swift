import MapKit
import Nav2PilotKit
import SwiftUI

/// What covers the map at each edge (panel, buttons): the camera and Apple's legal label keep clear of it.
struct MapInsets: Equatable {
    var top: CGFloat = 0
    var leading: CGFloat = 0
    var bottom: CGFloat = 0
    var trailing: CGFloat = 0
}

/// What the map draws. Passed as values (read in the parent's body), so SwiftUI updates the map whenever one changes.
struct MapContent: Equatable {
    var destination: Destination?
    var stops: [Destination] = []
    var routes: [RoutePreview] = []
    var selectedRouteIndex = 0
    var origin: LatLng?
    var recenterRequest = 0
}

/// The full-screen map: Apple Maps for everybody (free, no key), with Mapbox Streets tiles on top when the user has a
/// Mapbox token, so their Mapbox routes are shown on a Mapbox map. Shows the phone's position, the destination, the
/// stops and the routes; a tap reports itself or picks the route under it, a long press reports its coordinate.
struct NavMapView: UIViewRepresentable {
    let content: MapContent
    let mapboxToken: String?
    let insets: MapInsets
    let onTap: () -> Void
    let onLongPress: (Double, Double) -> Void
    let onSelectRoute: (Int) -> Void

    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = true
        map.pointOfInterestFilter = .includingAll
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.pinReuseId)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.delegate = context.coordinator
        map.addGestureRecognizer(longPress)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTap = onTap
        coordinator.onLongPress = onLongPress
        coordinator.onSelectRoute = onSelectRoute
        coordinator.selectedRouteIndex = content.selectedRouteIndex
        coordinator.routeColor = UIColor(Theme.brand)

        // Apple's legal label and the compass move with the margins
        map.layoutMargins = UIEdgeInsets(top: insets.top, left: insets.leading, bottom: insets.bottom, right: insets.trailing)

        coordinator.updateBaseMap(map, mapboxToken: mapboxToken, dark: colorScheme == .dark)
        coordinator.updateRoutes(map, routes: content.routes)
        coordinator.updatePins(map, destination: content.destination, stops: content.stops)
        coordinator.moveCamera(map, content: content, insets: insets)
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        static let pinReuseId = "pin"

        var onTap: () -> Void = {}
        var onLongPress: (Double, Double) -> Void = { _, _ in }
        var onSelectRoute: (Int) -> Void = { _ in }
        var selectedRouteIndex = 0
        var routeColor = UIColor.systemTeal

        private var baseMapKey = ""
        private var tileOverlay: MKTileOverlay?
        private var drawnRoutes: [RoutePreview] = []
        private var drawnSelected = -1
        private var routeLines: [RouteLine] = []
        private var drawnPinsKey = ""
        private var fitted: FitKey?
        private var recenterSeen = 0
        private var centeredOnce = false

        // MARK: base map

        func updateBaseMap(_ map: MKMapView, mapboxToken: String?, dark: Bool) {
            var key = "apple"
            if let token = mapboxToken, !token.isEmpty {
                key = "mapbox:" + token
                if dark {
                    key += ":dark"
                }
            }
            if key == baseMapKey {
                return
            }
            baseMapKey = key
            if let overlay = tileOverlay {
                map.removeOverlay(overlay)
                tileOverlay = nil
            }
            guard let token = mapboxToken, !token.isEmpty else {
                return
            }
            var style = "streets-v12"
            if dark {
                style = "dark-v11"
            }
            let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
            let template = "https://api.mapbox.com/styles/v1/mapbox/" + style + "/tiles/256/{z}/{x}/{y}@2x?access_token=" + encoded
            let overlay = MKTileOverlay(urlTemplate: template)
            overlay.canReplaceMapContent = true
            map.insertOverlay(overlay, at: 0, level: .aboveLabels)
            tileOverlay = overlay
        }

        // MARK: routes

        func updateRoutes(_ map: MKMapView, routes: [RoutePreview]) {
            if routes == drawnRoutes && selectedRouteIndex == drawnSelected {
                return
            }
            drawnRoutes = routes
            drawnSelected = selectedRouteIndex
            map.removeOverlays(routeLines)
            routeLines = []
            // unpicked routes first, so the picked one is drawn on top
            var order: [Int] = []
            for index in 0..<routes.count {
                if index != selectedRouteIndex {
                    order.append(index)
                }
            }
            if selectedRouteIndex < routes.count {
                order.append(selectedRouteIndex)
            }
            for index in order {
                let coordinates = Coordinator.coordinates(routes[index].coordinates)
                let line = RouteLine(coordinates: coordinates, count: coordinates.count)
                line.index = index
                routeLines.append(line)
                map.addOverlay(line, level: .aboveRoads)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tiles)
            }
            if let line = overlay as? RouteLine {
                let renderer = MKPolylineRenderer(polyline: line)
                if line.index == selectedRouteIndex {
                    renderer.strokeColor = routeColor
                    renderer.lineWidth = 7
                } else {
                    renderer.strokeColor = UIColor.systemGray
                    renderer.lineWidth = 5
                }
                renderer.lineCap = .round
                renderer.lineJoin = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        // MARK: pins

        func updatePins(_ map: MKMapView, destination: Destination?, stops: [Destination]) {
            var key = ""
            if let destination = destination {
                key = destination.coordinatesText()
            }
            for stop in stops {
                key += "|" + stop.coordinatesText()
            }
            if key == drawnPinsKey {
                return
            }
            drawnPinsKey = key
            var old: [MKAnnotation] = []
            for annotation in map.annotations {
                if annotation is Pin {
                    old.append(annotation)
                }
            }
            map.removeAnnotations(old)
            for (index, stop) in stops.enumerated() {
                let pin = Pin()
                pin.coordinate = CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)
                pin.stopNumber = index + 1
                map.addAnnotation(pin)
            }
            if let destination = destination {
                let pin = Pin()
                pin.coordinate = CLLocationCoordinate2D(latitude: destination.latitude, longitude: destination.longitude)
                pin.stopNumber = 0
                map.addAnnotation(pin)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? Pin else {
                // the phone's own position keeps the system blue dot
                return nil
            }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: Coordinator.pinReuseId, for: annotation)
            guard let marker = view as? MKMarkerAnnotationView else {
                return view
            }
            if pin.stopNumber == 0 {
                marker.markerTintColor = .systemRed
                marker.glyphImage = UIImage(systemName: "flag.checkered")
                marker.glyphText = nil
                marker.displayPriority = .required
            } else {
                marker.markerTintColor = .systemOrange
                marker.glyphImage = nil
                marker.glyphText = String(pin.stopNumber)
                marker.displayPriority = .required
            }
            marker.canShowCallout = false
            return marker
        }

        // MARK: camera

        /// The whole plan when the destination, the stops or the routes change; the phone's position on the recentre
        /// button, and once at start when there is nothing else to show.
        func moveCamera(_ map: MKMapView, content: MapContent, insets: MapInsets) {
            if content.recenterRequest != recenterSeen {
                recenterSeen = content.recenterRequest
                if let origin = content.origin {
                    centeredOnce = true
                    let center = CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude)
                    map.setRegion(MKCoordinateRegion(center: center, latitudinalMeters: 2500, longitudinalMeters: 2500), animated: true)
                    return
                }
            }

            let key = FitKey(routes: content.routes, destination: content.destination, stops: content.stops)
            if fitted != key {
                fitted = key
                if content.destination != nil {
                    fitPlan(map, content: content, insets: insets)
                    return
                }
            }

            if !centeredOnce && content.destination == nil, let origin = content.origin {
                centeredOnce = true
                let center = CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude)
                map.setRegion(MKCoordinateRegion(center: center, latitudinalMeters: 2500, longitudinalMeters: 2500), animated: false)
            }
        }

        private func fitPlan(_ map: MKMapView, content: MapContent, insets: MapInsets) {
            guard let destination = content.destination else {
                return
            }
            var points: [CLLocationCoordinate2D] = []
            for route in content.routes {
                points.append(contentsOf: Coordinator.coordinates(route.coordinates))
            }
            for stop in content.stops {
                points.append(CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude))
            }
            points.append(CLLocationCoordinate2D(latitude: destination.latitude, longitude: destination.longitude))
            if let origin = content.origin, !content.routes.isEmpty {
                points.append(CLLocationCoordinate2D(latitude: origin.latitude, longitude: origin.longitude))
            }
            var rect = MKMapRect.null
            for point in points {
                let mapPoint = MKMapPoint(point)
                rect = rect.union(MKMapRect(x: mapPoint.x, y: mapPoint.y, width: 0, height: 0))
            }
            // one point alone would zoom in to the maximum: about a kilometre around it
            let minimumSide = MKMapPointsPerMeterAtLatitude(destination.latitude) * 1200
            if rect.size.width < minimumSide && rect.size.height < minimumSide {
                rect = rect.insetBy(dx: -minimumSide / 2, dy: -minimumSide / 2)
            }
            let margin: CGFloat = 40
            let padding = UIEdgeInsets(
                top: insets.top + margin,
                left: insets.leading + margin,
                bottom: insets.bottom + margin,
                right: insets.trailing + margin
            )
            map.setVisibleMapRect(rect, edgePadding: padding, animated: true)
        }

        // MARK: gestures

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let map = recognizer.view as? MKMapView else {
                return
            }
            let index = routeAt(map, point: recognizer.location(in: map))
            if index >= 0 {
                onSelectRoute(index)
                return
            }
            onTap()
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            if recognizer.state != .began {
                return
            }
            guard let map = recognizer.view as? MKMapView else {
                return
            }
            let coordinate = map.convert(recognizer.location(in: map), toCoordinateFrom: map)
            onLongPress(coordinate.latitude, coordinate.longitude)
        }

        /// Our tap must not block the map's own gestures (pan, zoom, its double tap).
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            return true
        }

        /// The index of the unpicked route drawn under a tap, or -1.
        private func routeAt(_ map: MKMapView, point: CGPoint) -> Int {
            let reach: CGFloat = 14
            for line in routeLines.reversed() {
                if line.index == selectedRouteIndex {
                    continue
                }
                let points = line.points()
                for position in 0..<line.pointCount {
                    let screen = map.convert(points[position].coordinate, toPointTo: map)
                    let dx = screen.x - point.x
                    let dy = screen.y - point.y
                    if dx * dx + dy * dy <= reach * reach {
                        return line.index
                    }
                }
            }
            return -1
        }

        private static func coordinates(_ points: [LatLng]) -> [CLLocationCoordinate2D] {
            var result: [CLLocationCoordinate2D] = []
            for point in points {
                result.append(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
            }
            return result
        }
    }
}

/// A route on the map, with its index in the view model's list.
final class RouteLine: MKPolyline {
    var index = 0
}

/// The destination (stopNumber 0) or a stop (1, 2, …).
final class Pin: MKPointAnnotation {
    var stopNumber = 0
}

/// The camera moves again only when one of these changes, not when a route is picked.
private struct FitKey: Equatable {
    let routes: [RoutePreview]
    let destination: Destination?
    let stops: [Destination]
}

