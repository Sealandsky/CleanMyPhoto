

import SwiftUI

struct WelcomePage: View {
    @AppStorage("hasShownWelcome") private var hasShownWelcome: Bool = false
    @AppStorage("hasShownMembership") private var hasShownMembership: Bool = false

    var body: some View {
        VStack(spacing: 0) {

            Spacer()

            // 中间应用图标
            VStack(spacing: 24) {
                // 应用图标容器
                ZStack {
                    Image("WelcomeIcon")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .cornerRadius(22)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(.black, lineWidth: 0.5)
                                .padding(-2)
                                .opacity(0.27)
                        )
                }

                // 欢迎文字
                VStack(spacing: 8) {
                    Text(String(localized: "Welcome to Photato"))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)

                    Text(String(localized: "Maximize Your Photo Storage"))
                        .font(.system(size: 30, weight: .semibold))
                        .frame(width: 260)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            Spacer()

            // 底部按钮区域
            Button(action: {
                hasShownWelcome = true
            }) {
                HStack {
                    Text(String(localized: "Try 7 Days Free"))
                        .font(.system(size: 20, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .background(Color("PrimaryBtn"))
                .cornerRadius(22)
            }
            .padding(.horizontal, 32)
        }
        .background(Color.black)
    }
}

#Preview {
    WelcomePage()
}
