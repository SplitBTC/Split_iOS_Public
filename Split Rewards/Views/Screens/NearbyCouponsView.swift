//
//  NearbyCouponsView.swift
//  Split Rewards
//
//  Created by OpenAI on 4/14/26.
//

import SwiftUI
import CoreLocation

private struct CouponCoordinateSnapshot: Equatable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

struct NearbyCouponsView: View {
    private let background = Color.splitAppBlack
    private let cardSurface = Color.splitCardSurface
    private let blue = Color.splitBrandBlue
    private let pink = Color.splitBrandPink
    private let radiusMiles = 25.0

    @StateObject private var locationManager = NearbyCouponsLocationManager()

    @State private var coupons: [NearbyCoupon] = []
    @State private var searchOrigin: NearbyCouponSearchOrigin?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var hasStartedLookup = false
    @State private var lastLoadedCoordinate: CouponCoordinateSnapshot?
    @State private var showZipSheet = false
    @State private var showPromoInfo = false
    @State private var zipCode = ""
    @State private var zipErrorMessage: String?
    @State private var isSubmittingZip = false

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

                    Button {
                        showPromoInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        if isLoading && coupons.isEmpty {
                            loadingCard
                        } else if let errorMessage, coupons.isEmpty {
                            stateCard(
                                title: "Promos unavailable",
                                message: errorMessage,
                                isError: true
                            )
                        } else if coupons.isEmpty {
                            stateCard(
                                title: "No nearby promos yet",
                                message: "We couldn’t find any approved coupons within 25 miles of this area.",
                                isError: false
                            )
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(coupons) { coupon in
                                    NavigationLink(
                                        destination: NearbyCouponDetailView(
                                            coupon: coupon,
                                            onRedeemed: { redeemedAt in
                                                updateCouponRedemptionState(
                                                    couponId: coupon.id,
                                                    redeemedAt: redeemedAt
                                                )
                                            }
                                        )
                                    ) {
                                        couponCard(for: coupon)
                                    }
                                    .buttonStyle(.plain)
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
        .navigationTitle("Promos")
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
            Task { await loadCoupons(for: newSnapshot) }
        }
        .onChange(of: locationManager.locationRequestFailed) { _, didFail in
            guard didFail else { return }
            isLoading = false
            if coupons.isEmpty {
                errorMessage = "We couldn’t get your location. Enter a ZIP code to browse nearby promos."
                showZipSheet = true
            }
        }
        .sheet(isPresented: $showZipSheet) {
            NearbyCouponsZipSheet(
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
        .sheet(isPresented: $showPromoInfo) {
            PromoInfoSheet(pink: pink)
                .presentationDetents([.fraction(0.4)])
                .presentationDragIndicator(.visible)
        }
    }

    private var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)

            Text("Looking for nearby promos...")
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

    private func couponCard(for coupon: NearbyCoupon) -> some View {
        HStack(alignment: .top, spacing: 14) {
            couponLogo(for: coupon)

            VStack(alignment: .leading, spacing: 0) {
                Text(coupon.dealDescription)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.76))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func couponLogo(for coupon: NearbyCoupon) -> some View {
        let frame = CGSize(width: 68, height: 68)

        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)

            if let logoURLString = coupon.businessLogoUrl,
               let url = URL(string: logoURLString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                    default:
                        couponLogoFallback
                    }
                }
            } else {
                couponLogoFallback
            }
        }
        .frame(width: frame.width, height: frame.height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var couponLogoFallback: some View {
        Image(systemName: "tag.fill")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [blue.opacity(0.92), pink.opacity(0.88)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
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
            if coupons.isEmpty {
                showZipSheet = true
            }
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    @MainActor
    private func loadCoupons(for coordinate: CouponCoordinateSnapshot) async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await NearbyCouponsAPI.fetchNearbyCoupons(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                radiusMiles: radiusMiles
            )
            coupons = response.coupons
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
            let response = try await NearbyCouponsAPI.fetchNearbyCoupons(
                postalCode: normalizedZip,
                radiusMiles: radiusMiles
            )
            coupons = response.coupons
            searchOrigin = response.searchOrigin
            errorMessage = nil
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
                isLoading = true
                locationManager.requestLocationIfAuthorized()
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

        return "We couldn’t load nearby promos right now."
    }

    private func updateCouponRedemptionState(couponId: String, redeemedAt: String?) {
        guard let index = coupons.firstIndex(where: { $0.id == couponId }) else {
            return
        }

        coupons[index].hasRedeemedThisMonth = true
        coupons[index].currentUserRedeemedAt = redeemedAt
    }
}

private struct NearbyCouponsZipSheet: View {
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

                    Text("Location is unavailable. Enter a ZIP code and we’ll show approved promos within 25 miles.")
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

                                Text("Show Promos")
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

private final class NearbyCouponsLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var lastKnownCoordinate: CLLocationCoordinate2D?
    @Published var locationRequestFailed = false

    var coordinateSnapshot: CouponCoordinateSnapshot? {
        lastKnownCoordinate.map(CouponCoordinateSnapshot.init)
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

private enum NearbyCouponRedemptionDateHelper {
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

    static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "M/d hh:mma"
        return formatter
    }()

    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        if let fractionalDate = fractionalFormatter.date(from: value) {
            return fractionalDate
        }

        return standardFormatter.date(from: value)
    }

    static func displayString(from value: String?) -> String? {
        guard let date = parse(value) else { return nil }
        return displayFormatter.string(from: date).lowercased()
    }
}

private struct PromoInfoSheet: View {
    let pink: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.splitAppBlack,
                    Color.splitSurface
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(pink)

                        Text("Promo Info")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 8)

                    Text("Promos can be redeemed once a month. All promos become available on the 1st of every month (UTC time). Always confirm with merchant staff before redeeming a promo, and show the staff your screen while redeeming a promo.")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct NearbyCouponDetailView: View {
    let coupon: NearbyCoupon
    let onRedeemed: (String?) -> Void

    private let background = Color.splitAppBlack
    private let cardSurface = Color.splitCardSurface
    private let blue = Color.splitBrandBlue
    private let pink = Color.splitBrandPink

    @State private var hasRedeemedThisMonth: Bool
    @State private var currentUserRedeemedAt: String?
    @State private var showRedeemConfirmation = false
    @State private var showRedeemSuccess = false
    @State private var isRedeeming = false
    @State private var redeemErrorMessage: String?

    init(coupon: NearbyCoupon, onRedeemed: @escaping (String?) -> Void) {
        self.coupon = coupon
        self.onRedeemed = onRedeemed
        _hasRedeemedThisMonth = State(initialValue: coupon.hasRedeemedThisMonth)
        _currentUserRedeemedAt = State(initialValue: coupon.currentUserRedeemedAt)
    }

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    standaloneDetailLogo

                    sectionCard(title: "Promo") {
                        Text(coupon.dealDescription)
                            .font(.body)
                            .foregroundColor(.white.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    sectionCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(coupon.businessName)
                                .font(.headline.weight(.semibold))
                                .foregroundColor(.white)

                            Text(coupon.primaryBusinessAddress.formattedAddress)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.72))
                                .fixedSize(horizontal: false, vertical: true)

                            if coupon.appliesToAllLocations {
                                Text("Applies to all locations.")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(.white.opacity(0.60))
                            }

                            if let distanceMiles = coupon.distanceMiles {
                                Text(String(format: "%.1f miles away", distanceMiles))
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(.white.opacity(0.60))
                            }
                        }
                    }

                    if hasRedeemedThisMonth {
                        redeemedStatusCard
                    } else {
                        Button {
                            showRedeemConfirmation = true
                        } label: {
                            Text("Redeem")
                                .font(.headline.weight(.semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color.splitBrandPink)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isRedeeming)
                    }

                    Spacer(minLength: 10)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
        }
        .overlay {
            if showRedeemConfirmation {
                redeemConfirmationOverlay
            }
        }
        .alert(
            "Unable to Redeem Promo",
            isPresented: Binding(
                get: { redeemErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        redeemErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(redeemErrorMessage ?? "We couldn’t redeem this promo right now.")
        }
        .fullScreenCover(isPresented: $showRedeemSuccess) {
            NearbyCouponRedeemedSuccessView(coupon: coupon) {
                showRedeemSuccess = false
            }
        }
        .navigationTitle(coupon.businessName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var redeemedStatusCard: some View {
        Text(redeemedStatusText)
            .font(.headline.weight(.semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(cardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
    }

    private var redeemedStatusText: String {
        if let formattedDate = NearbyCouponRedemptionDateHelper.displayString(from: currentUserRedeemedAt) {
            return "Promo redeemed \(formattedDate)."
        }

        return "Promo redeemed."
    }

    private var redeemConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.66)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("Confirm the promo with merchant before redeeming")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button {
                        showRedeemConfirmation = false
                    } label: {
                        Text("Cancel")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isRedeeming)

                    Button {
                        Task { await redeemCoupon() }
                    } label: {
                        HStack(spacing: 8) {
                            if isRedeeming {
                                ProgressView()
                                    .tint(.white)
                            }

                            Text("Confirm")
                                .font(.headline.weight(.semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.splitBrandPink)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isRedeeming)
                }
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(cardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)
        }
    }

    @MainActor
    private func redeemCoupon() async {
        guard !isRedeeming else { return }
        isRedeeming = true

        do {
            let response = try await NearbyCouponsAPI.redeemCoupon(couponId: coupon.id)
            hasRedeemedThisMonth = response.didRedeem || response.alreadyRedeemedThisMonth
            currentUserRedeemedAt = response.redeemedAt
            onRedeemed(response.redeemedAt)
            showRedeemConfirmation = false

            if response.didRedeem {
                showRedeemSuccess = true
            }
        } catch {
            showRedeemConfirmation = false
            redeemErrorMessage = error.localizedDescription.isEmpty
                ? "We couldn’t redeem this promo right now."
                : error.localizedDescription
        }

        isRedeeming = false
    }

    @ViewBuilder
    private var standaloneDetailLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)

            if let logoURLString = coupon.businessLogoUrl,
               let url = URL(string: logoURLString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(10)
                    default:
                        detailLogoFallback
                    }
                }
            } else {
                detailLogoFallback
            }
        }
        .frame(width: 86, height: 86, alignment: .leading)
    }

    private var detailLogoFallback: some View {
        Image(systemName: "tag.fill")
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [blue, pink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private func sectionCard<Content: View>(title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct NearbyCouponRedeemedSuccessView: View {
    let coupon: NearbyCoupon
    let onDismiss: () -> Void

    @State private var animateTitle = false

    private let blue = Color.splitBrandBlue
    private let pink = Color.splitBrandPink

    var body: some View {
        ZStack {
            Color.splitAppBlack
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    pink.opacity(0.32),
                    blue.opacity(0.22),
                    Color.splitAppBlack.opacity(0.0)
                ],
                center: .top,
                startRadius: 40,
                endRadius: 420
            )
            .ignoresSafeArea()

            VStack(spacing: 26) {
                redeemedLogo

                Text("Promo Redeemed")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .scaleEffect(animateTitle ? 1.04 : 0.97)
                    .opacity(animateTitle ? 1.0 : 0.78)

                Text(coupon.businessName)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white.opacity(0.74))
            }
            .padding(.horizontal, 24)
        }
        .interactiveDismissDisabled()
        .task {
            animateTitle = true

            try? await Task.sleep(nanoseconds: 10_000_000_000)
            await MainActor.run {
                onDismiss()
            }
        }
        .animation(
            .easeInOut(duration: 1.05).repeatForever(autoreverses: true),
            value: animateTitle
        )
    }

    @ViewBuilder
    private var redeemedLogo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.white)

            if let logoURLString = coupon.businessLogoUrl,
               let url = URL(string: logoURLString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(20)
                    default:
                        redeemedLogoFallback
                    }
                }
            } else {
                redeemedLogoFallback
            }
        }
        .frame(width: 188, height: 188)
        .shadow(color: Color.black.opacity(0.26), radius: 24, x: 0, y: 16)
    }

    private var redeemedLogoFallback: some View {
        Image(systemName: "tag.fill")
            .font(.system(size: 56, weight: .semibold))
            .foregroundStyle(
                LinearGradient(
                    colors: [blue, pink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }
}
