//
//  WelcomePage.swift
//  CleanMyPhoto
//
//  Created by 陈嘉华 on 2026/2/15.
//


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
                    Text("欢迎使用 CleanMyPhotos")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)

                    Text("最大程度节省手机图片空间")
                        .font(.system(size: 30, weight: .semibold))
                        .frame(width: 260)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            Spacer()

            // 底部按钮区域
            VStack(spacing: 16) {
                // 开始使用按钮（查看会员选项）
                Button(action: {
                    hasShownWelcome = true
                    // 保持 hasShownMembership = false，显示会员页
                }) {
                    HStack {
                        Text("开始使用")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .background(Color("PrimaryBtn"))
                    .cornerRadius(22)
                }
                .padding(.horizontal, 32)

                // 试用按钮（直接跳过会员页）
                Button(action: {
                    hasShownWelcome = true
                    hasShownMembership = true // 跳过会员页
                }) {
                    HStack {
                        Text("试用 3 天")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .background(Color.white.opacity(0.12))
                    .cornerRadius(22)
                }
                .padding(.horizontal, 32)
            }
        }
        .background(Color.black)
    }
}

#Preview {
    WelcomePage()
}
