//
//  BTCMerchantMapView.swift
//  Split Rewards
//
//  Created by TeeVee on 3/24/26.
//

import SwiftUI
import MapKit
import CoreLocation

private struct EquatableCoordinate: Equatable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct BTCMerchantMapView: View {
    private struct PlacePin: Identifiable {
        let place: BTCMapPlace
        var id: Int { place.id }

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon)
        }
    }

    private let fallbackCenter = CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795)
    private let surface = Color.splitInputSurface
    private let accentPink = Color.splitBrandPink

    @StateObject private var locationManager = BTCMerchantMapLocationManager()
    @State private var position: MapCameraPosition
    @State private var visibleRegion: MKCoordinateRegion
    @State private var places: [BTCMapPlace] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedPlace: BTCMapPlace?
    @State private var lastQueryKey: String?
    @State private var hasCenteredOnUserLocation = false

    init() {
        let initialRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795),
            span: MKCoordinateSpan(latitudeDelta: 18, longitudeDelta: 24)
        )
        _position = State(initialValue: .region(initialRegion))
        _visibleRegion = State(initialValue: initialRegion)
    }

    private var pins: [PlacePin] {
        places.map { PlacePin(place: $0) }
    }

    private var merchantMap: some View {
        Map(
            position: $position,
            interactionModes: .all
        ) {
            ForEach(pins) { pin in
                Annotation(pin.place.name ?? "Merchant", coordinate: pin.coordinate) {
                    mapPinButton(for: pin)
                }
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            merchantMap
            .ignoresSafeArea(edges: .bottom)
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                Task { await refreshIfNeeded(force: false) }
            }
            .overlay(alignment: .top) {
                mapHeader
            }

            if isLoading && places.isEmpty {
                ProgressView()
                    .tint(.white)
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.black.opacity(0.78))
                    )
            }
        }
        .navigationTitle("BTC Merchants")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            locationManager.startOnLaunch()
            await refreshIfNeeded(force: true)
        }
        .onChange(of: locationManager.equatableLastKnownCoordinate) { _, newValue in
            guard let newValue, !hasCenteredOnUserLocation else { return }
            hasCenteredOnUserLocation = true
            centerMap(on: newValue.clCoordinate, latitudeDelta: 0.03, longitudeDelta: 0.03)
            Task { await refreshIfNeeded(force: true) }
        }
        .sheet(item: $selectedPlace) { place in
            BTCMerchantPlaceDetailSheet(place: place)
        }
    }

    private func mapPinButton(for pin: PlacePin) -> some View {
        Button {
            selectedPlace = pin.place
        } label: {
            BTCMerchantMapPin(isSelected: selectedPlace?.id == pin.id)
        }
        .buttonStyle(.plain)
    }

    private var mapHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "storefront.fill")
                    .foregroundStyle(accentPink)

                Text("BTC Merchant Map")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))

                Spacer()

                Button {
                    if let coordinate = locationManager.lastKnownCoordinate {
                        centerMap(on: coordinate, latitudeDelta: 0.03, longitudeDelta: 0.03)
                        Task { await refreshIfNeeded(force: true) }
                    } else {
                        if locationManager.authorizationStatus == .authorizedAlways
                            || locationManager.authorizationStatus == .authorizedWhenInUse {
                            locationManager.activateIfAuthorized()
                        } else {
                            locationManager.requestAuthorizationIfNeeded()
                        }
                        centerMap(on: fallbackCenter, latitudeDelta: 18, longitudeDelta: 24)
                        Task { await refreshIfNeeded(force: true) }
                    }
                } label: {
                    Image(systemName: "scope")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Recenter map")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.red.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Paid a bitcoin-accepting merchant and didn't get rewarded? Submit the business from your transaction details. We'll add them to our rewards program ASAP.")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Text("Just tap the")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white.opacity(0.60))

                        Image(systemName: "storefront.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white)

                        Text("in your transaction.")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.white.opacity(0.60))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    @MainActor
    private func refreshIfNeeded(force: Bool) async {
        let queryKey = currentQueryKey(for: visibleRegion)
        guard force || queryKey != lastQueryKey else { return }

        lastQueryKey = queryKey
        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await GetBTCMapPlacesAPI.fetchPlaces(
                latitude: visibleRegion.center.latitude,
                longitude: visibleRegion.center.longitude,
                radiusKilometers: searchRadius(for: visibleRegion)
            )
            places = fetched
        } catch {
            if places.isEmpty {
                errorMessage = "Couldn’t load BTC merchants right now."
            } else {
                errorMessage = "Couldn’t refresh this area right now."
            }
        }

        isLoading = false
    }

    private func currentQueryKey(for region: MKCoordinateRegion) -> String {
        let lat = String(format: "%.4f", region.center.latitude)
        let lon = String(format: "%.4f", region.center.longitude)
        let radius = String(format: "%.2f", searchRadius(for: region))
        return "\(lat)|\(lon)|\(radius)"
    }

    private func searchRadius(for region: MKCoordinateRegion) -> Double {
        let latKm = region.span.latitudeDelta * 111.0
        let lonKm = region.span.longitudeDelta * 111.0 * cos(region.center.latitude * .pi / 180.0)
        let radius = max(latKm, abs(lonKm)) * 0.55
        return min(max(radius, 0.05), 50)
    }

    private func centerMap(
        on coordinate: CLLocationCoordinate2D,
        latitudeDelta: CLLocationDegrees,
        longitudeDelta: CLLocationDegrees
    ) {
        withAnimation {
            let region = MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(
                    latitudeDelta: latitudeDelta,
                    longitudeDelta: longitudeDelta
                )
            )
            position = .region(region)
            visibleRegion = region
        }
    }
}

private final class BTCMerchantMapLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var lastKnownCoordinate: CLLocationCoordinate2D?

    var equatableLastKnownCoordinate: EquatableCoordinate? {
        lastKnownCoordinate.map(EquatableCoordinate.init)
    }

    private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.authorizationStatus = .notDetermined
        self.lastKnownCoordinate = nil
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        bootstrapCurrentState()
    }

    private func bootstrapCurrentState() {
        let manager = self.manager

        Task.detached {
            let status = manager.authorizationStatus
            let coordinate = manager.location?.coordinate

            await MainActor.run {
                self.authorizationStatus = status
                self.lastKnownCoordinate = coordinate

                if status == .authorizedAlways || status == .authorizedWhenInUse {
                    manager.startUpdatingLocation()
                }
            }
        }
    }

    func requestAuthorizationIfNeeded() {
        guard authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func startOnLaunch() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            activateIfAuthorized()
        }
    }

    func activateIfAuthorized() {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .notDetermined, .restricted, .denied:
            break
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus

        Task { @MainActor in
            authorizationStatus = status
        }

        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        case .restricted, .denied, .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let coordinate = locations.last?.coordinate {
            Task { @MainActor in
                lastKnownCoordinate = coordinate
            }
        }
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        manager.stopUpdatingLocation()
    }
}

private struct BTCMerchantMapPin: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.90))
                .frame(width: 34, height: 34)

            Image(systemName: "storefront.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(isSelected ? Color.splitBrandPink : .white, .black)
        }
        .shadow(color: .black.opacity(0.26), radius: 5, x: 0, y: 2)
    }
}

private struct BTCMerchantPlaceDetailSheet: View {
    let place: BTCMapPlace

    private let surface = Color.splitInputSurface
    private let secondarySurface = Color.splitInputSurfaceSecondary

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        media

                        VStack(alignment: .leading, spacing: 12) {
                            Text(place.name?.nilIfBlank ?? "BTC Merchant")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)

                            if let address = place.address?.nilIfBlank {
                                detailRow(systemName: "mappin.and.ellipse", value: address)
                            }

                            if let provider = place.paymentProvider?.nilIfBlank {
                                detailRow(systemName: "bolt.fill", value: provider.capitalized)
                            }

                            if let verifiedAt = place.verifiedAt?.nilIfBlank {
                                detailRow(systemName: "checkmark.seal.fill", value: "Verified \(verifiedAt)")
                            }

                            if let description = place.description?.nilIfBlank {
                                Text(description)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.76))
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            VStack(spacing: 12) {
                                if let website = place.website?.nilIfBlank,
                                   let url = URL(string: website) {
                                    Link(destination: url) {
                                        actionPill(
                                            systemName: "safari.fill",
                                            title: "Open Website"
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }

                                if let osmURL = place.osmURL?.nilIfBlank,
                                   let url = URL(string: osmURL) {
                                    Link(destination: url) {
                                        actionPill(
                                            systemName: "map.fill",
                                            title: "Open in OpenStreetMap"
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }

                                if let mapsURL = appleMapsURL {
                                    Link(destination: mapsURL) {
                                        actionPill(
                                            systemName: "location.fill",
                                            title: "Open in Apple Maps"
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 6)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var media: some View {
        ZStack {
            if let imageURLString = place.image?.nilIfBlank,
               let url = URL(string: imageURLString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallbackMedia
                    }
                }
            } else {
                fallbackMedia
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var fallbackMedia: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.splitBrandBlue.opacity(0.28),
                    Color.splitBrandPink.opacity(0.24),
                    Color.black.opacity(0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "storefront.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundColor(.white.opacity(0.86))
        }
    }

    private func detailRow(systemName: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.68))
                .frame(width: 18, height: 18)

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actionPill(systemName: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))

            Text(title)
                .font(.system(size: 15, weight: .semibold))

            Spacer(minLength: 0)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(secondarySurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var appleMapsURL: URL? {
        let urlString = "http://maps.apple.com/?ll=\(place.lat),\(place.lon)&q=\((place.name?.nilIfBlank ?? "BTC Merchant").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "BTC%20Merchant")"
        return URL(string: urlString)
    }
}

#Preview {
    NavigationStack {
        BTCMerchantMapView()
    }
}
