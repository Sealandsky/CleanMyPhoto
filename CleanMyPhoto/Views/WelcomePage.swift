//
//  WelcomePage.swift
//  BookMark
//
//  欢迎页 - 首次启动时显示
//

import SwiftUI

struct WelcomePage: View {
    @State private var showMainApp = false

    var body: some View {
        ZStack {

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
                        Text("欢迎使用 BookMark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("记录阅读时光，发现更好的自己")
                            .font(.system(size: 30, weight: .semibold))
                            .frame(width: 260)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }

                Spacer()

                // 底部按钮区域
                VStack(spacing: 16) {
                    // 开始使用按钮
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showMainApp = true
                        }
                    }) {
                        HStack {
                            Text("开始使用")
                                .font(.system(size: 20, weight: .semibold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 72)
                        .background(AppColors.groupedBackground)
                        .cornerRadius(22)
                    }
                    .padding(.horizontal, 32)
                }
            }
        }
        .overlay {
            if showMainApp {
                ContentView()
                    .transition(.opacity)
            }
            
        }
    }
}

#Preview {
    WelcomePage()
}
