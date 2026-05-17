import SwiftUI
import UIKit
import PhotosUI

struct FoodScanView: View {
    @State private var viewModel = FoodScanViewModel()
    @State private var showImagePicker = false
    @State private var imagePickerSource: ImagePickerSource = .camera
    @State private var showConfirm = false
    @State private var showDescribeSheet = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryBackground.ignoresSafeArea()
                contentView
            }
            .navigationTitle("Log Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showProviderPicker = true
                    } label: {
                        Label(viewModel.selectedProvider.displayName.components(separatedBy: " ").first ?? "AI",
                              systemImage: viewModel.selectedProvider.systemImage)
                        .font(DesignTokens.Typography.footnote)
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showProviderPicker) {
                NutritionProviderPickerSheet(viewModel: viewModel, supportsVision: true)
            }
            .sheet(isPresented: $showImagePicker) {
                ImagePickerView(source: imagePickerSource) { image in
                    showImagePicker = false
                    Task { await viewModel.scanImage(image) }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showDescribeSheet) {
                DescribeMealSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showConfirm) {
                if let meal = viewModel.editableMeal {
                    NutritionConfirmView(meal: meal, viewModel: viewModel)
                }
            }
            .onChange(of: viewModel.state) { _, newState in
                // Only drive confirm sheet for the photo path (describe sheet handles its own flow)
                if case .confirming = newState, !showDescribeSheet {
                    showConfirm = true
                }
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.state {
        case .idle:
            idleView
        case .scanning:
            scanningView
        case .error(let msg):
            errorView(msg)
        case .success(let meal):
            successView(meal)
        default:
            idleView
        }
    }

    private var idleView: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: DesignTokens.Spacing.xs) {
                Text("Log Your Meal")
                    .font(DesignTokens.Typography.title2)
                    .foregroundStyle(.primaryText)
                Text("Take a photo, choose from your library, or describe your meal in words.")
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignTokens.Spacing.xl)
            }

            // Context input (for photo modes)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text("Add context for photo scan (optional)")
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(.secondaryText)
                TextField("e.g. large Chipotle burrito bowl", text: $viewModel.userContext)
                    .textFieldStyle(.roundedBorder)
                    .font(DesignTokens.Typography.body)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)

            // Action buttons
            VStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    triggerHaptic(.medium)
                    imagePickerSource = .camera
                    showImagePicker = true
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .padding(.horizontal, DesignTokens.Spacing.md)

                Button {
                    triggerHaptic(.light)
                    imagePickerSource = .photoLibrary
                    showImagePicker = true
                } label: {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.sm)
                }
                .buttonStyle(.bordered)
                .tint(Color.accentColor)
                .padding(.horizontal, DesignTokens.Spacing.md)

                // Divider with "or"
                HStack {
                    Rectangle().fill(Color.tertiaryText.opacity(0.4)).frame(height: 1)
                    Text("or")
                        .font(DesignTokens.Typography.footnote)
                        .foregroundStyle(.tertiaryText)
                        .padding(.horizontal, DesignTokens.Spacing.xs)
                    Rectangle().fill(Color.tertiaryText.opacity(0.4)).frame(height: 1)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)

                Button {
                    triggerHaptic(.light)
                    showDescribeSheet = true
                } label: {
                    Label("Describe Your Meal", systemImage: "text.bubble")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignTokens.Spacing.sm)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .padding(.horizontal, DesignTokens.Spacing.md)
            }

            Spacer()
        }
    }

    private var scanningView: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color.accentColor)
            Text("Analysing your meal…")
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(.primaryText)
            Text("Identifying ingredients and estimating nutrition")
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(.secondaryText)
            Spacer()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
            Text("Analysis Failed")
                .font(DesignTokens.Typography.title2)
                .foregroundStyle(.primaryText)
            Text(message)
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignTokens.Spacing.xl)
            Button("Try Again") { viewModel.reset() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    private func successView(_ meal: ScannedMeal) -> some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Logged to Apple Health!")
                .font(DesignTokens.Typography.title2)
                .foregroundStyle(.primaryText)
            Text(meal.foodName)
                .font(DesignTokens.Typography.headline)
                .foregroundStyle(.secondaryText)
            Text("\(Int(meal.nutrition.calories)) kcal")
                .font(DesignTokens.Typography.callout)
                .foregroundStyle(Color.accentColor)
            Button("Log Another") { viewModel.reset() }
                .buttonStyle(.bordered)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
    }
}

// MARK: - Describe Meal Sheet

struct DescribeMealSheet: View {
    @Bindable var viewModel: FoodScanViewModel
    @State private var description: String = ""
    @State private var mealDate: Date = Date()
    @State private var isAnalysing = false
    @State private var errorMessage: String? = nil
    @State private var showConfirm = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextFocused: Bool

    private var canSubmit: Bool {
        !isAnalysing && description.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.primaryBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {

                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.1))
                                    .frame(width: 72, height: 72)
                                Image(systemName: "text.bubble.fill")
                                    .font(.system(size: 32, weight: .light))
                                    .foregroundStyle(Color.accentColor)
                            }
                            Spacer()
                        }
                        .padding(.top, DesignTokens.Spacing.md)

                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                            Text("What did you eat?")
                                .font(DesignTokens.Typography.headline)
                                .foregroundStyle(.primaryText)
                            Text("Describe your meal — include portion sizes, ingredients, and cooking method for the most accurate estimate.")
                                .font(DesignTokens.Typography.footnote)
                                .foregroundStyle(.secondaryText)
                        }

                        // Text editor
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                            Text("Meal description")
                                .font(DesignTokens.Typography.footnote)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondaryText)

                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                    .fill(Color.cardBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                                            .stroke(isTextFocused ? Color.accentColor : Color.tertiaryText.opacity(0.3),
                                                    lineWidth: isTextFocused ? 1.5 : 1)
                                    )

                                if description.isEmpty {
                                    Text("e.g. Large Cajun chicken burrito bowl with basmati rice, black beans, sour cream and guacamole")
                                        .font(DesignTokens.Typography.body)
                                        .foregroundStyle(.tertiaryText)
                                        .padding(DesignTokens.Spacing.sm)
                                        .allowsHitTesting(false)
                                }

                                TextEditor(text: $description)
                                    .font(DesignTokens.Typography.body)
                                    .foregroundStyle(.primaryText)
                                    .scrollContentBackground(.hidden)
                                    .background(Color.clear)
                                    .focused($isTextFocused)
                                    .frame(minHeight: 120)
                                    .padding(DesignTokens.Spacing.xs)
                            }

                            HStack {
                                Spacer()
                                Text("\(description.count) characters")
                                    .font(DesignTokens.Typography.caption2)
                                    .foregroundStyle(.tertiaryText)
                            }
                        }

                        // Meal date/time
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                            Text("When did you eat this?")
                                .font(DesignTokens.Typography.footnote)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondaryText)

                            DatePicker("", selection: $mealDate, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .tint(Color.accentColor)
                        }

                        tipCard

                        Button {
                            submitDescription()
                        } label: {
                            HStack(spacing: DesignTokens.Spacing.xs) {
                                if isAnalysing {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "sparkles")
                                }
                                Text(isAnalysing ? "Estimating…" : "Estimate Nutrition with AI")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DesignTokens.Spacing.sm)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.accentColor)
                        .disabled(!canSubmit)
                        .opacity(canSubmit ? 1 : 0.6)
                        .animation(.easeInOut(duration: 0.2), value: isAnalysing)
                    }
                    .padding(DesignTokens.Spacing.md)
                }

                // Full-screen loading overlay
                if isAnalysing {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    VStack(spacing: DesignTokens.Spacing.md) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Estimating nutrition…")
                            .font(DesignTokens.Typography.headline)
                            .foregroundStyle(.white)
                        Text("AI is analysing your meal")
                            .font(DesignTokens.Typography.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(DesignTokens.Spacing.xl)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
                }
            }
            .navigationTitle("Describe Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        viewModel.reset()
                        dismiss()
                    }
                    .disabled(isAnalysing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.showProviderPicker = true
                    } label: {
                        Label(viewModel.selectedProvider.displayName.components(separatedBy: " ").first ?? "AI",
                              systemImage: viewModel.selectedProvider.systemImage)
                        .font(DesignTokens.Typography.footnote)
                        .foregroundStyle(Color.accentColor)
                    }
                    .disabled(isAnalysing)
                }
            }
            .sheet(isPresented: $viewModel.showProviderPicker) {
                NutritionProviderPickerSheet(viewModel: viewModel, supportsVision: false)
            }
            .sheet(isPresented: $showConfirm, onDismiss: {
                // If user cancelled confirm, reset so they can try again
                if case .confirming = viewModel.state { viewModel.reset() }
                // If logged successfully, close describe sheet too
                if case .success = viewModel.state { dismiss() }
            }) {
                if let meal = viewModel.editableMeal {
                    NutritionConfirmView(meal: meal, viewModel: viewModel)
                }
            }
            .alert("Analysis Failed", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Try Again") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func submitDescription() {
        triggerHaptic(.medium)
        isTextFocused = false
        isAnalysing = true
        errorMessage = nil

        Task { @MainActor in
            viewModel.mealDate = mealDate
            await viewModel.describeFood(description)
            isAnalysing = false

            switch viewModel.state {
            case .confirming:
                showConfirm = true
            case .error(let msg):
                errorMessage = msg
            default:
                break
            }
        }
    }

    private var tipCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Label("Tips for better estimates", systemImage: "lightbulb.fill")
                .font(DesignTokens.Typography.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(Color.orange)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                tipRow("Include portion sizes (e.g. \"large\", \"200g\", \"1 cup\")")
                tipRow("Name the main protein and cooking method")
                tipRow("Mention sauces, toppings and sides")
                tipRow("Name the restaurant if it's takeaway")
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }

    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.xs) {
            Text("•")
                .font(DesignTokens.Typography.footnote)
                .foregroundStyle(.secondaryText)
            Text(text)
                .font(DesignTokens.Typography.footnote)
                .foregroundStyle(.secondaryText)
        }
    }
}

// MARK: - Nutrition Provider Picker Sheet

/// Mirrors QueryView's ProviderPickerSheet but for the Nutrition Log feature.
/// supportsVision=true: on-device is marked as "Text only" (vision not supported).
/// supportsVision=false (Describe Meal): on-device is fully available.
struct NutritionProviderPickerSheet: View {
    var viewModel: FoodScanViewModel
    let supportsVision: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.allProviderModels, id: \.0) { provider, models in
                    Section {
                        ForEach(models) { model in
                            let isOnDevice = model.isOnDevice
                            let visionUnavailable = supportsVision && isOnDevice
                            let needsKey = !isOnDevice && !viewModel.hasKey(for: provider)
                            let isSelected = viewModel.selectedProvider == provider && viewModel.selectedModelID == model.id

                            Button {
                                if !visionUnavailable && !needsKey {
                                    viewModel.setProvider(provider, modelID: model.id)
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: DesignTokens.Spacing.sm) {
                                    Image(systemName: provider.systemImage)
                                        .foregroundStyle(isSelected ? Color.accentColor : .secondaryText)
                                        .frame(width: 20)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.displayName)
                                            .font(DesignTokens.Typography.body)
                                            .foregroundStyle(needsKey || visionUnavailable ? .tertiaryText : .primaryText)

                                        if visionUnavailable {
                                            Text("Text-only · Not available for photo scan")
                                                .font(DesignTokens.Typography.caption2)
                                                .foregroundStyle(.orange)
                                        } else if needsKey {
                                            Text("API key required — configure in Settings")
                                                .font(DesignTokens.Typography.caption2)
                                                .foregroundStyle(.orange)
                                        } else {
                                            Text("4096 tokens · \(isOnDevice ? "On-device" : "Cloud")")
                                                .font(DesignTokens.Typography.caption2)
                                                .foregroundStyle(.tertiaryText)
                                        }
                                    }

                                    Spacer()

                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                    } else if visionUnavailable || needsKey {
                                        Image(systemName: "lock.fill")
                                            .foregroundStyle(.tertiaryText)
                                    }
                                }
                            }
                            .disabled(visionUnavailable || needsKey)
                        }
                    } header: {
                        Label(provider.displayName, systemImage: provider.systemImage)
                    }
                }
            }
            .navigationTitle("Select AI Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Image Picker Source

enum ImagePickerSource {
    case camera
    case photoLibrary
}

// MARK: - UIImagePickerController Wrapper

struct ImagePickerView: UIViewControllerRepresentable {
    let source: ImagePickerSource
    let onImageSelected: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        switch source {
        case .camera:
            picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        case .photoLibrary:
            picker.sourceType = .photoLibrary
        }
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageSelected: onImageSelected)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImageSelected: (UIImage) -> Void

        init(onImageSelected: @escaping (UIImage) -> Void) {
            self.onImageSelected = onImageSelected
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImageSelected(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
