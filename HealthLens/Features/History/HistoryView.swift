import SwiftUI
import SwiftData

struct HistoryView: View {
    @State private var viewModel = HistoryViewModel()
    @Environment(NavigationRouter.self) private var router
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \AnalysisSession.createdAt, order: .reverse)
    private var allSessions: [AnalysisSession]

    private var filteredSessions: [AnalysisSession] {
        viewModel.filtered(allSessions)
    }

    private var grouped: [(HistoryViewModel.DateBucket, [AnalysisSession])] {
        viewModel.grouped(filteredSessions)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                // Filter bar
                filterBar
                    .padding(.bottom, DesignTokens.Spacing.sm)

                if filteredSessions.isEmpty {
                    emptyState
                } else {
                    ForEach(grouped, id: \.0.rawValue) { bucket, sessions in
                        Section {
                            ForEach(sessions) { session in
                                SessionRowView(
                                    session: session,
                                    onTap: { router.openSession(session.id) },
                                    onFavorite: {
                                        session.isFavorited.toggle()
                                        try? modelContext.save()
                                    }
                                )
                                .padding(.horizontal, DesignTokens.Spacing.md)
                                .padding(.bottom, DesignTokens.Spacing.xs)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        modelContext.delete(session)
                                        try? modelContext.save()
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }

                                    Button {
                                        session.isFavorited.toggle()
                                        try? modelContext.save()
                                    } label: {
                                        Label(session.isFavorited ? "Unfav" : "Fav",
                                              systemImage: session.isFavorited ? "star.slash" : "star.fill")
                                    }
                                    .tint(.yellow)
                                }
                            }
                        } header: {
                            Text(bucket.rawValue)
                                .font(DesignTokens.Typography.footnote)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondaryText)
                                .padding(.horizontal, DesignTokens.Spacing.md)
                                .padding(.vertical, DesignTokens.Spacing.xs)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primaryBackground)
                        }
                    }
                }

                Spacer(minLength: DesignTokens.Spacing.xxl)
            }
        }
        .background(Color.primaryBackground)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $viewModel.searchText, prompt: "Search analyses")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Favorites Only", isOn: $viewModel.showFavoritesOnly)
                    Divider()
                    Menu("Filter by Provider") {
                        Button("All Providers") { viewModel.selectedProvider = nil }
                        ForEach(AIProviderType.allCases, id: \.self) { provider in
                            Button(provider.displayName) { viewModel.selectedProvider = provider }
                        }
                    }
                    if !allSessions.isEmpty {
                        Divider()
                        Button("Delete All", role: .destructive) {
                            allSessions.forEach { modelContext.delete($0) }
                            try? modelContext.save()
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                // Favorites chip
                filterChip(
                    label: "Favorites",
                    icon: "star.fill",
                    color: .yellow,
                    isSelected: viewModel.showFavoritesOnly
                ) {
                    viewModel.showFavoritesOnly.toggle()
                }

                Divider().frame(height: 20)

                ForEach(HealthCategory.allCases, id: \.rawValue) { category in
                    filterChip(
                        label: category.displayName,
                        icon: category.systemImage,
                        color: category.color,
                        isSelected: viewModel.selectedCategories.contains(category)
                    ) {
                        triggerHaptic(.selection)
                        if viewModel.selectedCategories.contains(category) {
                            viewModel.selectedCategories.remove(category)
                        } else {
                            viewModel.selectedCategories.insert(category)
                        }
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
        }
    }

    private func filterChip(label: String, icon: String, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 10))
                Text(label).font(DesignTokens.Typography.caption).fontWeight(.medium)
            }
            .foregroundStyle(isSelected ? .white : color)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(isSelected ? color : color.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: viewModel.searchText.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.tertiaryText)
            Text(viewModel.searchText.isEmpty ? "No analysis sessions yet" : "No results for '\(viewModel.searchText)'")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(.secondaryText)
            if viewModel.searchText.isEmpty {
                Text("Ask a question on the Ask tab to get started")
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DesignTokens.Spacing.xxl)
    }
}
