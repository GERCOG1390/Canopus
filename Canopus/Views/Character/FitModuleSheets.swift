// Per-module settings and the charge picker of the fit screen.

import SwiftUI
import EVEAuth
import EVEStaticData
import Domain
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Module Setting Sheet

struct ModuleSettingSheet: View {
    let item: ESIFittingItem
    let typeName: String
    let moduleAttrs: [Int: Double]
    let moduleEffectIds: Set<Int>
    @Binding var config: ModuleConfig
    @Binding var chargeNames: [Int: String]
    @Binding var chargeTypeAttrs: [Int: [Int: Double]]
    var onRemove: (() -> Void)? = nil
    /// Called when a charge is selected; allows the caller to broadcast to all identical weapons.
    var onChargeSelected: ((ItemType, [Int: Double]) -> Void)? = nil

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var showChargePicker = false

    private var isWeapon: Bool {
        [604, 605, 606, 609].contains { (moduleAttrs[$0] ?? 0) > 0 }
    }
    private var pgCost: Double  { moduleAttrs[30] ?? 0 }
    private var cpuCost: Double { moduleAttrs[50] ?? 0 }

    /// The module has an overload effect (from the parent's ModuleActivation).
    var canOverload = false
    private var isActiveMod: Bool { canOverload }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.eveBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {

                        // Module info card
                        HStack(spacing: 14) {
                            EVETypeIcon(typeId: item.typeId, size: 52)
                                .clipShape(CutCorner(size: 8))
                                .overlay(CutCorner(size: 8).stroke(Color.eveAmber.opacity(0.25), lineWidth: 1))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(typeName)
                                    .font(.ui(16, .semibold))
                                    .foregroundStyle(Color.eveText)
                                HStack(spacing: 12) {
                                    if pgCost > 0 {
                                        Label { Text(String(format: "%.0f MW", pgCost)) } icon: { GameIcon.attribute(30, size: 14) }
                                            .font(.ui(11)).foregroundStyle(Color.eveAmber.opacity(0.75))
                                    }
                                    if cpuCost > 0 {
                                        Label { Text(String(format: "%.0f Tf", cpuCost)) } icon: { GameIcon.attribute(50, size: 14) }
                                            .font(.ui(11)).foregroundStyle(Color.eveCyan.opacity(0.75))
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(20)

                        Color.eveAmber.opacity(0.12).frame(height: 1)

                        // State picker
                        VStack(alignment: .leading, spacing: 10) {
                            Text("MODULE STATE").hudLabel()
                            HStack(spacing: 8) {
                                ForEach(ModuleState.allCases, id: \.self) { state in
                                    let enabled = state != .overload || isActiveMod
                                    Button {
                                        guard enabled else { return }
                                        config.state = state
                                    } label: {
                                        EVEModuleStateBadge(
                                            state: state,
                                            isSelected: config.state == state,
                                            isEnabled: enabled
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!enabled)
                                }
                            }
                            Text(config.state.rawValue)
                                .font(.ui(11, .medium)).monospacedDigit()
                                .foregroundStyle(config.state.dotColor.opacity(0.72))
                        }
                        .padding(.horizontal, 20).padding(.vertical, 14)

                        if isWeapon {
                            Color.eveAmber.opacity(0.12).frame(height: 1)

                            // Charge section
                            VStack(alignment: .leading, spacing: 10) {
                                Text("AMMO / CHARGE").hudLabel()

                                NavigationLink {
                                    ChargePickerView(
                                        weaponTypeId: item.typeId,
                                        selectedChargeId: config.chargeTypeId
                                    ) { charge, attrs in
                                        config.chargeTypeId = charge.id
                                        if let broadcast = onChargeSelected {
                                            broadcast(charge, attrs)
                                        } else {
                                            chargeNames[charge.id] = charge.name
                                            chargeTypeAttrs[charge.id] = attrs
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text("Charge")
                                            .font(.ui(14)).foregroundStyle(Color.eveText)
                                        Spacer()
                                        if let cid = config.chargeTypeId, let name = chargeNames[cid] {
                                            Text(name)
                                                .font(.ui(13)).foregroundStyle(Color.eveAmber)
                                                .lineLimit(1)
                                        } else {
                                            Text("None").font(.ui(13)).foregroundStyle(Color.eveText.opacity(0.35))
                                        }
                                        EVEActionIndicator(kind: .navigate)
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(Color.eveCard)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)

                                if let cid = config.chargeTypeId,
                                   let attrs = chargeTypeAttrs[cid] {
                                    ChargeDamageBreakdown(profile: ChargeDamageProfile(attrs: attrs))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(Color.eveCard.opacity(0.65))
                                        .clipShape(CutCorner(size: 6))
                                }

                                if config.chargeTypeId != nil {
                                    Button {
                                        config.chargeTypeId = nil
                                    } label: {
                                        Text("Clear Charge")
                                            .font(.ui(13, .medium))
                                            .foregroundStyle(Color.eveRed)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20).padding(.vertical, 14)
                        }

                        if let onRemove {
                            Color.eveAmber.opacity(0.12).frame(height: 1)

                            Button(role: .destructive) {
                                onRemove()
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Text("✕")
                                        .font(.ui(13, .semibold))
                                    Text("REMOVE MODULE")
                                        .font(.ui(11, .semibold)).monospacedDigit()
                                        .tracking(1.0)
                                    Spacer()
                                }
                                .foregroundStyle(Color.eveRed)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                .background(Color.eveBackground)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("MODULE SETTING")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.eveBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.eveCyan)
                }
            }
        }
    }
}

// MARK: - Charge Picker

struct ChargePickerView: View {
    let weaponTypeId: Int
    let selectedChargeId: Int?
    let onSelect: (ItemType, [Int: Double]) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var charges: [ItemType] = []
    @State private var chargeAttrMaps: [Int: [Int: Double]] = [:]
    @State private var isLoading = true
    @State private var search = ""

    private var filtered: [ItemType] {
        if search.isEmpty { return charges }
        return charges.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        ZStack {
            Color.eveBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Glyph(name: .search, size: 16)
                        .foregroundStyle(Color.eveText.opacity(0.40))
                    TextField("Search", text: $search)
                        .font(.ui(14))
                        .foregroundStyle(Color.eveText)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color.eveCard)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 16).padding(.vertical, 10)

                Color.eveAmber.opacity(0.12).frame(height: 1)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if filtered.isEmpty && !isLoading {
                            EmptyState("No Compatible Charges", icon: "win_warning") { Text("No ammunition found for this weapon.") }
                            .foregroundStyle(Color.eveText)
                            .padding(.top, 40)
                        }
                        ForEach(filtered, id: \.id) { charge in
                            chargeRow(charge)
                            EVESeparator()
                        }
                    }
                    .padding(.bottom, EVELayout.scrollBottomClearance)
                }
            }
            if isLoading { ProgressView().tint(Color.eveCyan) }
        }
        .navigationTitle("SELECT CHARGE")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.eveBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await loadCharges() }
    }

    private func chargeRow(_ charge: ItemType) -> some View {
        let isSelected = charge.id == selectedChargeId
        let attrs = chargeAttrMaps[charge.id] ?? [:]
        let damage = ChargeDamageProfile(attrs: attrs)

        return Button {
            onSelect(charge, attrs)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                EVETypeIcon(typeId: charge.id, size: 36)
                    .clipShape(CutCorner(size: 5))
                    .overlay(CutCorner(size: 5).stroke(
                        isSelected ? Color.eveAmber.opacity(0.5) : Color.white.opacity(0.07),
                        lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    Text(charge.name)
                        .font(.ui(14))
                        .foregroundStyle(isSelected ? Color.eveAmber : Color.eveText)
                        .lineLimit(1)
                    ChargeDamageBreakdown(profile: damage, compact: true)
                }

                Spacer()

                if isSelected {
                    Text("✓")
                        .font(.ui(12, .semibold))
                        .foregroundStyle(Color.eveAmber)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 9)
            .background(Color.eveBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadCharges() async {
        isLoading = true; defer { isLoading = false }
        guard let repo = env.repository else { return }
        charges = (try? await repo.compatibleCharges(weaponTypeId: weaponTypeId)) ?? []
        let ids = Set(charges.map(\.id))
        if let maps = try? await repo.typeAttributeMaps(typeIds: ids) {
            chargeAttrMaps = maps
        }
    }
}
