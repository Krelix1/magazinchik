import SwiftUI

enum AccountAuthMode: Equatable {
    case signIn
    case createAccount
}

/// Local checks. Firebase is not called when a field is empty or the two passwords differ.
enum AccountAuthForm {
    static func rejection(
        mode: AccountAuthMode,
        email: String,
        password: String,
        confirmation: String
    ) -> String? {
        if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Введите почту."
        }
        if password.isEmpty {
            return "Введите пароль."
        }
        guard mode == .createAccount else { return nil }
        if confirmation.isEmpty {
            return "Повторите пароль."
        }
        if password != confirmation {
            return "Пароли не совпадают."
        }
        return nil
    }
}

/// Sign-in and account creation. One dark screen, opened from Settings. Not a form row.
struct AccountAuthView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CardSyncService.self) private var sync

    @State private var mode: AccountAuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var passwordVisible = false
    @State private var confirmationVisible = false
    @State private var message: String?

    private var busy: Bool { sync.phase == .signingIn }

    private var actionTitle: String {
        mode == .signIn ? "Войти" : "Создать аккаунт"
    }

    private var progressTitle: String {
        mode == .signIn ? "Вход…" : "Создание…"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Магазинчик")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("Карты следуют за вами на другой телефон.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 12) {
                        emailField
                        passwordField(
                            text: $password,
                            prompt: "Пароль",
                            visible: $passwordVisible,
                            contentType: mode == .signIn ? .password : .newPassword
                        )
                        if mode == .createAccount {
                            passwordField(
                                text: $confirmation,
                                prompt: "Пароль ещё раз",
                                visible: $confirmationVisible,
                                contentType: .newPassword
                            )
                        }
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        Text(busy ? progressTitle : actionTitle)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.black.opacity(busy ? 0.45 : 1))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white.opacity(busy ? 0.45 : 1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)

                    if let message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Color(hex: "FF9F0A"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: toggleMode) {
                        Text(mode == .signIn ? "Нет аккаунта? Создать" : "Уже есть аккаунт? Войти")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(hex: "0A0A0A").ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .tint(.primary)
                    .accessibilityLabel("Закрыть")
                }
                .glassToolbarItem()
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: sync.accountEmail) { _, email in
            if email != nil { dismiss() }
        }
    }

    private var emailField: some View {
        TextField(
            "Эл. почта",
            text: $email,
            prompt: Text("Эл. почта").foregroundStyle(.secondary)
        )
        .textContentType(.emailAddress)
        .keyboardType(.emailAddress)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .padding(16)
        .background(Color(hex: "161618"), in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func passwordField(
        text: Binding<String>,
        prompt: String,
        visible: Binding<Bool>,
        contentType: UITextContentType
    ) -> some View {
        HStack(spacing: 12) {
            Group {
                if visible.wrappedValue {
                    TextField(prompt, text: text, prompt: Text(prompt).foregroundStyle(.secondary))
                } else {
                    SecureField(prompt, text: text, prompt: Text(prompt).foregroundStyle(.secondary))
                }
            }
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            Button {
                visible.wrappedValue.toggle()
            } label: {
                Image(systemName: visible.wrappedValue ? "eye.slash" : "eye")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(visible.wrappedValue ? "Скрыть пароль" : "Показать пароль")
        }
        .padding(16)
        .background(Color(hex: "161618"), in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func toggleMode() {
        mode = mode == .signIn ? .createAccount : .signIn
        confirmation = ""
        confirmationVisible = false
        message = nil
    }

    private func submit() async {
        if let rejection = AccountAuthForm.rejection(
            mode: mode,
            email: email,
            password: password,
            confirmation: confirmation
        ) {
            message = rejection
            return
        }
        message = nil
        switch mode {
        case .signIn:
            await sync.signIn(email: email, password: password)
        case .createAccount:
            await sync.createAccount(email: email, password: password)
        }
        if sync.accountEmail == nil {
            message = sync.lastError ?? "Не удалось войти. Попробуйте ещё раз."
        }
    }
}
