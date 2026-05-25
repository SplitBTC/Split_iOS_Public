import SwiftUI
import Foundation
import CoreLocation

private struct BitcoinEventCoordinateSnapshot: Equatable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

private struct BitcoinEventSearchOrigin: Decodable, Hashable {
    let source: String
    let latitude: Double
    let longitude: Double
    let postalCode: String?
    let formattedAddress: String?
}

private struct BitcoinEventItem: Decodable, Identifiable, Hashable {
    let id: String
    let source: String
    let sourceUrl: String
    let externalEventId: String
    let title: String
    let description: String
    let coverImageUrl: String
    let hostName: String
    let startsAt: String
    let endsAt: String?
    let timezone: String
    let venueName: String
    let address: String
    let city: String
    let region: String
    let postalCode: String
    let country: String
    let latitude: Double?
    let longitude: Double?
    let distanceMiles: Double?
}

private struct BitcoinEventsResponse: Decodable {
    let nearbyEvents: [BitcoinEventItem]
    let moreEvents: [BitcoinEventItem]
    let searchOrigin: BitcoinEventSearchOrigin?
    let radiusMiles: Double
}

private struct BitcoinEventsErrorResponse: Decodable {
    let error: String
}

private enum BitcoinEventsAPI {
    static func fetchEvents(
        latitude: Double,
        longitude: Double
    ) async throws -> BitcoinEventsResponse {
        var components = URLComponents(string: "\(AppConfig.baseURL)/v1/bitcoin-events")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude))
        ]

        return try await performRequest(with: components)
    }

    static func fetchEvents(postalCode: String) async throws -> BitcoinEventsResponse {
        var components = URLComponents(string: "\(AppConfig.baseURL)/v1/bitcoin-events")
        components?.queryItems = [
            URLQueryItem(name: "postalCode", value: postalCode)
        ]

        return try await performRequest(with: components)
    }

    private static func performRequest(with components: URLComponents?) async throws -> BitcoinEventsResponse {
        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(BitcoinEventsErrorResponse.self, from: data)
            let raw = String(data: data, encoding: .utf8) ?? ""
            let message = apiError?.error ?? raw

            throw NSError(
                domain: "BitcoinEventsAPI",
                code: httpResponse.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        message.isEmpty
                        ? "Server error (HTTP \(httpResponse.statusCode))"
                        : message
                ]
            )
        }

        return try JSONDecoder().decode(BitcoinEventsResponse.self, from: data)
    }
}

struct BitcoinEventsView: View {
    private let background = Color.splitAppBlack
    private let cardSurface = Color.splitCardSurface
    private let blue = Color.splitBrandBlue
    private let pink = Color.splitBrandPink

    @Environment(\.openURL) private var openURL
    @StateObject private var locationManager = BitcoinEventsLocationManager()

    @State private var nearbyEvents: [BitcoinEventItem] = []
    @State private var moreEvents: [BitcoinEventItem] = []
    @State private var searchOrigin: BitcoinEventSearchOrigin?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var hasStartedLookup = false
    @State private var lastLoadedCoordinate: BitcoinEventCoordinateSnapshot?
    @State private var showZipSheet = false
    @State private var zipCode = ""
    @State private var zipErrorMessage: String?
    @State private var isSubmittingZip = false
    @State private var showAllEvents = false

    private var sortedNearbyEvents: [BitcoinEventItem] {
        sortedEvents(nearbyEvents)
    }

    private var sortedAllEvents: [BitcoinEventItem] {
        var seenIds = Set<String>()
        let dedupedEvents = (nearbyEvents + moreEvents).filter { event in
            seenIds.insert(event.id).inserted
        }

        return sortedEvents(dedupedEvents)
    }

    private var visibleEvents: [BitcoinEventItem] {
        showAllEvents ? sortedAllEvents : sortedNearbyEvents
    }

    private var emptyStateTitle: String {
        showAllEvents ? "No events listed yet" : "No nearby events yet"
    }

    private var emptyStateMessage: String {
        showAllEvents
            ? "We don’t have any upcoming Bitcoin events across the US yet."
            : "We couldn’t find any Bitcoin events within 25 miles of this area."
    }

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        zipErrorMessage = nil
                        showZipSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "number.square")
                                .font(.system(size: 13, weight: .semibold))

                            Text("Use ZIP Code")
                                .font(.footnote.weight(.semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.10))
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    HStack(spacing: 14) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showAllEvents = false
                            }
                        } label: {
                            Text("Nearby")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(showAllEvents ? .white : pink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showAllEvents = true
                            }
                        } label: {
                            Text("All Events")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(showAllEvents ? pink : .white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 10)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        if isLoading && visibleEvents.isEmpty {
                            loadingCard
                        } else if let errorMessage, visibleEvents.isEmpty {
                            stateCard(
                                title: "Events unavailable",
                                message: errorMessage,
                                isError: true
                            )
                        } else if visibleEvents.isEmpty {
                            stateCard(
                                title: emptyStateTitle,
                                message: emptyStateMessage,
                                isError: false
                            )
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(visibleEvents) { event in
                                    eventCard(for: event)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
                .refreshable {
                    await refreshSearch()
                }
            }
        }
        .navigationTitle("Bitcoin Events")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await beginLookupIfNeeded()
        }
        .onChange(of: locationManager.authorizationStatus) { _, newStatus in
            handleAuthorizationChange(newStatus)
        }
        .onChange(of: locationManager.coordinateSnapshot) { _, newSnapshot in
            guard let newSnapshot else { return }
            guard lastLoadedCoordinate != newSnapshot else { return }
            lastLoadedCoordinate = newSnapshot
            Task { await loadEvents(for: newSnapshot) }
        }
        .onChange(of: locationManager.locationRequestFailed) { _, didFail in
            guard didFail else { return }
            isLoading = false
            if nearbyEvents.isEmpty {
                errorMessage = "We couldn’t get your location. Enter a ZIP code to browse nearby Bitcoin events."
                showZipSheet = true
            }
        }
        .sheet(isPresented: $showZipSheet) {
            BitcoinEventsZipSheet(
                zipCode: $zipCode,
                errorMessage: zipErrorMessage,
                isSubmitting: isSubmittingZip,
                onSubmit: {
                    Task { await submitZipCode() }
                },
                onCancel: {
                    zipErrorMessage = nil
                    showZipSheet = false
                }
            )
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
    }

    private var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)

            Text("Looking for nearby Bitcoin events...")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func stateCard(title: String, message: String, isError: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)

            Text(message)
                .font(.subheadline)
                .foregroundColor(isError ? Color.white.opacity(0.80) : Color.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                zipErrorMessage = nil
                showZipSheet = true
            } label: {
                Text("Enter ZIP Code")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(pink.opacity(0.92))
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func eventCard(for event: BitcoinEventItem) -> some View {
        Button {
            if let url = URL(string: event.sourceUrl) {
                openURL(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                eventCover(for: event)

                VStack(alignment: .leading, spacing: 9) {
                    Text(event.title)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        eventMetaRow(
                            icon: "calendar",
                            text: BitcoinEventDateHelper.displayString(
                                startsAt: event.startsAt,
                                timezone: event.timezone
                            )
                        )

                        eventMetaRow(
                            icon: "mappin.and.ellipse",
                            text: locationLine(for: event)
                        )

                        if !event.hostName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            eventMetaRow(icon: "person.2.fill", text: event.hostName)
                        }
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(cardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func eventCover(for event: BitcoinEventItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [blue.opacity(0.22), pink.opacity(0.20)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let url = URL(string: event.coverImageUrl),
               !event.coverImageUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        eventCoverFallback
                    }
                }
            } else {
                eventCoverFallback
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1.9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .topLeading) {
            Text(distanceText(for: event))
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.54))
                )
                .padding(10)
        }
    }

    private var eventCoverFallback: some View {
        Image(systemName: "calendar.badge.clock")
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [blue.opacity(0.95), pink.opacity(0.90)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private func eventMetaRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(blue)
                .frame(width: 16, height: 16)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.72))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func locationLine(for event: BitcoinEventItem) -> String {
        let venue = event.venueName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cityState = [event.city, event.region]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        if !venue.isEmpty && !cityState.isEmpty {
            return "\(venue) • \(cityState)"
        }

        return venue.isEmpty ? cityState : venue
    }

    private func distanceText(for event: BitcoinEventItem) -> String {
        guard let distance = event.distanceMiles else {
            return "Nearby"
        }

        if distance < 0.1 {
            return "Near you"
        }

        return "\(distance.cleanDistanceString) mi"
    }

    private func sortedEvents(_ events: [BitcoinEventItem]) -> [BitcoinEventItem] {
        events.sorted { lhs, rhs in
            let lhsDate = BitcoinEventDateHelper.parse(lhs.startsAt) ?? .distantFuture
            let rhsDate = BitcoinEventDateHelper.parse(rhs.startsAt) ?? .distantFuture
            return lhsDate < rhsDate
        }
    }

    @MainActor
    private func beginLookupIfNeeded() async {
        guard !hasStartedLookup else { return }
        hasStartedLookup = true

        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isLoading = true
            errorMessage = nil
            locationManager.requestLocationIfAuthorized()
        case .notDetermined:
            isLoading = true
            errorMessage = nil
            locationManager.requestAccessOrLocation()
        case .restricted, .denied:
            isLoading = false
            showZipSheet = true
        @unknown default:
            isLoading = false
            showZipSheet = true
        }
    }

    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            errorMessage = nil
            isLoading = true
            locationManager.requestLocationIfAuthorized()
        case .restricted, .denied:
            isLoading = false
            if nearbyEvents.isEmpty {
                showZipSheet = true
            }
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    @MainActor
    private func loadEvents(for coordinate: BitcoinEventCoordinateSnapshot) async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await BitcoinEventsAPI.fetchEvents(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            nearbyEvents = response.nearbyEvents
            moreEvents = response.moreEvents
            searchOrigin = response.searchOrigin
        } catch {
            errorMessage = userFacingErrorMessage(for: error)
        }

        isLoading = false
    }

    @MainActor
    private func submitZipCode() async {
        let normalizedZip = normalizedPostalCode(zipCode)

        guard isValidPostalCode(normalizedZip) else {
            zipErrorMessage = "Enter a valid ZIP code."
            return
        }

        zipCode = normalizedZip
        zipErrorMessage = nil
        isSubmittingZip = true
        isLoading = true

        do {
            let response = try await BitcoinEventsAPI.fetchEvents(postalCode: normalizedZip)
            nearbyEvents = response.nearbyEvents
            moreEvents = response.moreEvents
            searchOrigin = response.searchOrigin
            errorMessage = nil
            showAllEvents = false
            showZipSheet = false
        } catch {
            zipErrorMessage = userFacingErrorMessage(for: error)
        }

        isSubmittingZip = false
        isLoading = false
    }

    @MainActor
    private func refreshSearch() async {
        if let searchOrigin {
            switch searchOrigin.source {
            case "postalCode":
                zipCode = searchOrigin.postalCode ?? zipCode
                await submitZipCode()
            default:
                if let lastLoadedCoordinate {
                    await loadEvents(for: lastLoadedCoordinate)
                } else {
                    isLoading = true
                    locationManager.requestLocationIfAuthorized()
                }
            }
            return
        }

        await beginLookupIfNeeded()
    }

    private func normalizedPostalCode(_ value: String) -> String {
        let digits = value.filter(\.isNumber)

        if digits.count > 5 {
            let prefix = digits.prefix(5)
            let suffix = digits.dropFirst(5).prefix(4)
            return suffix.isEmpty ? String(prefix) : "\(prefix)-\(suffix)"
        }

        return String(digits.prefix(5))
    }

    private func isValidPostalCode(_ value: String) -> Bool {
        let digits = value.filter(\.isNumber)
        return digits.count == 5 || digits.count == 9
    }

    private func userFacingErrorMessage(for error: Error) -> String {
        let raw = error.localizedDescription

        if raw.contains("That ZIP code") || raw.contains("We could not") || raw.contains("Enter a valid US ZIP code") {
            return raw
        }

        return "We couldn’t load nearby Bitcoin events right now."
    }
}

private struct BitcoinEventsZipSheet: View {
    @Binding var zipCode: String

    let errorMessage: String?
    let isSubmitting: Bool
    let onSubmit: () -> Void
    let onCancel: () -> Void

    @FocusState private var isZipFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.splitAppBlack
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    Text("Enter ZIP Code")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.white)

                    Text("Location is unavailable. Enter a ZIP code and we’ll show Bitcoin events within 25 miles.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("ZIP code", text: $zipCode)
                            .keyboardType(.numberPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isZipFocused)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.splitInputSurface)
                            )
                            .onChange(of: zipCode) { _, newValue in
                                let digits = newValue.filter(\.isNumber)

                                if digits.count > 5 {
                                    let prefix = digits.prefix(5)
                                    let suffix = digits.dropFirst(5).prefix(4)
                                    zipCode = suffix.isEmpty ? String(prefix) : "\(prefix)-\(suffix)"
                                } else {
                                    zipCode = String(digits.prefix(5))
                                }
                            }

                        if let errorMessage, !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.caption.weight(.medium))
                                .foregroundColor(Color(red: 1, green: 0.7, blue: 0.82))
                        }
                    }

                    HStack(spacing: 12) {
                        Button(action: onCancel) {
                            Text("Cancel")
                                .font(.headline)
                                .foregroundColor(.white.opacity(0.80))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)

                        Button(action: onSubmit) {
                            HStack(spacing: 8) {
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                }

                                Text("Show Events")
                                    .font(.headline)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.splitBrandBlue, Color.splitBrandPink],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isSubmitting)
                    }

                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                isZipFocused = true
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private final class BitcoinEventsLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var lastKnownCoordinate: CLLocationCoordinate2D?
    @Published var locationRequestFailed = false

    var coordinateSnapshot: BitcoinEventCoordinateSnapshot? {
        lastKnownCoordinate.map(BitcoinEventCoordinateSnapshot.init)
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
            }
        }
    }

    func requestAccessOrLocation() {
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            requestLocationIfAuthorized()
        case .restricted, .denied:
            break
        @unknown default:
            break
        }
    }

    func requestLocationIfAuthorized() {
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else {
            return
        }

        locationRequestFailed = false
        manager.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus

        Task { @MainActor in
            authorizationStatus = status
        }

        if status == .authorizedAlways || status == .authorizedWhenInUse {
            requestLocationIfAuthorized()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }

        Task { @MainActor in
            locationRequestFailed = false
            lastKnownCoordinate = coordinate
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationRequestFailed = true
        }
    }
}

private enum BitcoinEventDateHelper {
    static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let standardFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        if let fractionalDate = fractionalFormatter.date(from: value) {
            return fractionalDate
        }

        return standardFormatter.date(from: value)
    }

    static func displayString(startsAt: String, timezone: String) -> String {
        guard let date = parse(startsAt) else {
            return "Date TBD"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timezone) ?? .current
        formatter.dateFormat = "EEE, MMM d • h:mm a"

        return formatter.string(from: date)
    }
}

private extension Double {
    var cleanDistanceString: String {
        if self >= 10 {
            return String(Int(self.rounded()))
        }

        return String(format: "%.1f", self)
    }
}
